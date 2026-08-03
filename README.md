# Cache Memory Controller

## Table of Contents

- [Features](#features)
- [FPGA Resource Utilization](#fpga-resource-utilization)
- [Design Considerations](#design-considerations)
- [RAM Instantiations](#ram-instantiations)
  - [Tag RAM](#tag-ram)
  - [Valid Bit RAM](#valid-bit-ram)
  - [Data RAM](#data-ram)
- [Block Architecture](#block-architecture)
- [Hit/Miss Sequence](#hitmiss-sequence)
  - [Cache Hit](#cache-hit)
  - [Cache Miss](#cache-miss)
  - [Address Generation Unit (AGU)](#address-generation-unit-agu)
  - [Writing on a Cache Hit](#writing-on-a-cache-hit)
- [FSM Diagram](#fsm-diagram)
- [Verification](#verification)
- [Future Improvements](#future-improvements)

## Overview
This project is a synthesizable VHDL implementation of an L1 direct mapped cache that explores cache controllers, FSM design, cache protocols, and memory management. While intentionally simple compared to modern processor caches, it implements the core mechanisms required for a functional cache controller, including tag comparison, line fills, write-through protocol, and cache miss handling. When I continue working on this project and make future iterations, for an L1 cache, I would explore associativity as opposed to directly mapped, and also replace the simple write through protocol to a write back protocol with least recently used algorithm for the replacement policy. This would increase complexity by a lot, but more accurately mimic L1 cache.

## Features
| Specification | Value |
|--------------|-------|
| Cache Size | 1 KB |
| Mapping | Direct-mapped |
| Cache Lines | 64 |
| Words per Line | 4 |
| Word Width | 32 bits |
| Line Width | 128 bits |
| Hit Latency | 1 cycle |
| Miss Latency | 9 cycles |
| Write Policy | Write-through |

## FPGA Resource Utilization
| Resource | Utilization |
|----------|-------------|
| Logic Elements | 623 |
| Registers | 198 |
| Memory Bits | 9,792 |
| Fmax (Worst Case) | 135 MHz |

Timing was measured after Quartus synthesis using the default worst-case timing model.

## Design Considerations
This project uses direct mapped memory in cache, meaning that each address from the CPU can correspond to exactly one spot in memory of this cache. In contrast, a set-associative cache allows an address to be placed in any way within a set, reducing conflict misses (line already filled) at the cost of additional hardware complexity. 

To understand this, note that in a cache implementation like this that contains only 64 cache lines, it must support the entire 32-bit address space. The 6-bit index selects one of the 64 cache lines, leaving the remaining 24 bits as the tag. As a result, each cache line may represent 2^24 (16,777,216) different memory blocks over time. An address that shares the same index but has different tags results in those two address competing for the same cache line. This becomes problematic because data we might not want to be overwritten must always be due to the limitations of direct mapped cache. In an associative cache, instead of directly mapping and overwriting whatever was there before, there can be additional algorithms to decide how data gets overwritten.

CPU address Breakdown:
| Address Bits | Purpose |
|-------------|---------|
| 31:8 | Tag (24 bits) |
| 7:2 | Index (6 bits) |
| 1:0 | Word Offset (2 bits) |

The way that the memory gets handled in this cache is mainly revolving around the index. Since the index is 6 bits, this corresponds to the 64 lines we have in the cache (2^6 combinations). There are 3 different inferred RAM instantiations, each holding a different set of information needed for the controller. All 3 RAMs receive the index as the "address in" for that Ram. By doing this, it enables the ability to write to the given RAMs using the cpu inputs, or to read from what is currently stored in the Ram.

## RAM Instantiations

The cache is implemented using three inferred synchronous RAM blocks: a Tag RAM, Valid Bit RAM, and Data RAM.

### Tag RAM
  The first RAM is the tag ram. This stores the 24 bit tag that is currently being used at the selected index of that line. This is because since our RAM blocks only hold the index, each cache line can actually hold addresses
  
0x000000XX to 0xFFFFFFXX

Where the bottom 2 bytes correspond to the index and offset. So therefore, the tag must be stored in this RAM so we actually know what address information we are holding. This essentially allows the working address to be extended from the 64 memory spaces in the cache RAM, to include the extra 24 bits of the tag. The cache RAM blocks can still only hold 64 lines at a time, but by using a RAM dedicated to the tag, it allows it to represent much more than 0 - 63 in memory. 

### Valid Bit RAM
  The next Ram is the valid bit RAM. This is a very simple block in this implementation, as it gets initialized to 0, meaning that the cache line is not valid, and then once written to one time, it becomes 1. This design only uses 1 extra valid bit, but in a better implementation, it would additionally have a "dirty bit", meaning that the data is no longer matching the ram. But in my implementation, when writing on a cache hit, it follows a write through protocol and writes directly to RAM to ensure they stay synced. Additionally, on a cache miss, the controller first writes to RAM, then caches the whole line; as opposed to caching the line, and then writing to the address in cache.

### Data RAM
  The last Ram is the data RAM. This holds the data that is located in the cache line currently. The data RAM holds 128 bit lines, containing 4 32 bit words. Before being output the 128 bits get sliced into the 32 bit segments, where the offset (the bottom 2 bits of the cpu address) select one of the words. This essentially means that each cache line can hold 4 addresses of memory (00 to 11).

## Block Architecture
This is the high level architecture of the cache, with some minor details being left out, and not including the control bits from the cache controller. It does show the Ram instantiations, and the CPU address slicing. Additionally another part shown is the output buffer for Ram address generation. This can be explained better in the FSM section.
<img width="822" height="810" alt="Cache_Arch" src="https://github.com/user-attachments/assets/997160a2-a90a-4bdc-b529-bb1e4574a979" />


## Hit/Miss Sequence
### Cache Hit
This FSM diagram better shows the cache write protocol. On a cache hit, the data will be available in 1 cycle (with the 1 cycle latency being from the synchronous RAM blocks instantiated within the cache that require 1 cycle to return data). 

  So the hit sequence is:

1. Read tag/data/valid RAM
2. Compare tags
3. Return data
4. Write-through on write requests

It can also be noted that in a write hit, after completing the CPU request, the controller writes through to Ram in the following cycle, to sync the cache to RAM. 

### Cache Miss
  On a cache miss, the sequence is:

1. Write straight to ram on write request
2. Generate aligned address
3. Fetch four words
4. Assemble cache line
5. Write into cache data block
6. Return CPU request

The latency is 9 cycles for a read miss, and 10 cycles for a write miss (the extra cycle coming from the initial write through to RAM). These cycles are mostly as a result to the interface inferred to external RAM. This FSM design is inferring an interface to a 1 word (32 bit wide) external RAM rather than a multi-word wide RAM, or an L2 cache. As a result, this means that data can only come in 32 bits at a time, resulting in 4 cycles being used to cache the whole line. On an L1 cache miss, but L2 cache hit, these cycles would be reduced by 4 (assuming same width of L1 and L2 cache), and therefore reduce the cycle count to 5 and 6 respectively on a miss.


### Address Generation Unit (AGU)
  The next important part of that is the RAM address generation. The AGU has two functions. It can either use the cpu address in on the initial write request (write through), or it can be used to cache an entire line at a time from RAM. This is done by clearing the bottom 2 bits of the cpu address(the offset), and incrementing from 00 to 11, and storing each of the data at those locations. 
  Another consideration of this is the shift register needed to bring in 32 bits at a time and fill the 128 bit line needed by the data RAM (worth noting that this is more accurately represented, and is synthesized as a mux due to no synchronous behavior, but it can be understood as shifting the bits in at 32 bit words).

### Writing on a Cache Hit
  The last quirk handled in this topology is how a cache hit on a write request gets handled. Since 128 bits are held in a cache line, and the CPU only provides 32 bits to be written back, this also needs to get handled with a read-modify-write function from the data RAM. This gets handled by having a MUX that allows 32 bits of the current stored data, to be overwritten by CPU data depending on the offset, and that gets written back into the data RAM.

## FSM Diagram
<img width="909" height="1095" alt="Cache_FSM" src="https://github.com/user-attachments/assets/1c5328b3-fc04-4b72-8c71-61532ad59522" />



## Verification
  Since this design infers external RAM, the write through functionality could not be properly verified without additional design (although the external Ram interface is very basic and would need more consideration to target a real external RAM). The part that could be verified of the RAM interface is the AGU, the Ram data out, and the read and write controls. 
  This design was verified in ModelSim using a test bench that would read within a cache line (to cache the whole line), and then writing to each of those words that are now cached, and then reading them to verify it properly wrote. The reason it needs to be done like this is because the cache is only able to be written to directly, meaning we can't write on a miss, and have the actual data be there(because external Ram wont provide any data). So the initial read is in order to have the 4 addresses available in cache to write to them locally, and then read them from there.
  
Verified functionality

- Cold read miss
- Line fill
- Cache hit writes
- Cache hit reads
- Tag comparison
- Offset-based word selection
- External RAM address generation

## Future Improvements

- 2-way and 4-way set-associative organization
- Write-back cache with dirty bits
- LRU replacement policy (implemented using a binary tree–based pseudo-LRU algorithm)
- Multi-level cache hierarchy (exploring different policies optimized for improved hit rate and reduced miss latency)
- Burst memory interface


## Repository Structure

```text
.
├── rtl/
│   ├── Source
│   │     └── cache.vhd
│   ├── Testbench
│   │     └── cache_tb.vhd
├── quartus/
│   ├── cache.qsf
│   └── cache.qpf
├── images/
│   └── cache_sim_wave.png
└── README.md
```

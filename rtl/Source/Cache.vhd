library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache is
	generic(
	awidth    : positive:= 32;
	dwidth    : positive:= 32
	);
	port(
	-- cpu inputs
	cpu_ain    : in std_logic_vector(awidth-1 downto 0);
	cpu_din    : in std_logic_vector(dwidth-1 downto 0);
	cpu_read   : in std_logic;
	cpu_write  : in std_logic;
	
	clk		  : in std_logic;
	rst		  : in std_logic;
	
	-- ram data
	ram_din    : in std_logic_vector(dwidth-1 downto 0);
	ram_dout   : out std_logic_vector(dwidth-1 downto 0);
	
	-- cache out to cpu
	cpu_dout   : out std_logic_vector(dwidth-1 downto 0);
	cpu_stall  : out std_logic;
	req_done   : out std_logic;
	
	-- ram addressing
	ram_aout   : out std_logic_vector(awidth-1 downto 0);
	ram_rd     : out std_logic;
	ram_wr     : out std_logic
	);
	
end cache;


library ieee;
use ieee.std_logic_1164.all;

entity buffer_reg is
	generic(
	dwidth : positive
	);
	port(
	D      : in std_logic_vector(dwidth-1 downto 0);
	Q      : out std_logic_vector(dwidth-1 downto 0);
	en     : in  std_logic;
	
	clk    : in std_logic;
	rst    : in std_logic
	);
end buffer_reg;

architecture bhv of buffer_reg is
begin
	process(clk, rst)
    begin
        if (rst = '1') then
            Q <= (others => '0');   
        elsif (rising_edge(clk)) then
            if (en = '1') then
                Q <= D;
            end if;
        end if;
    end process;
end bhv;


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- inferred ram block
entity general_ram is
	generic(
	dwidth  : positive;
	awidth  : positive
	);
	port(
	clk     : in std_logic;
	rd_en   : in std_logic;
	rd_addr : in std_logic_vector(awidth-1 downto 0);
	rd_data : out std_logic_vector(dwidth-1 downto 0);
	wr_en   : in std_logic;
	wr_addr : in std_logic_vector(awidth-1 downto 0);
	wr_data : in std_logic_vector(dwidth-1 downto 0)
	);
end general_ram;

architecture bhv of general_ram is
	type   ram_array is array (0 to 2**awidth-1) of std_logic_vector(dwidth-1 downto 0);
	signal ram : ram_array;
begin
	process (clk)
    begin
        if (rising_edge(clk)) then
            if (wr_en = '1') then
                ram(to_integer(unsigned(wr_addr))) <= wr_data;
            end if;

            if (rd_en = '1') then
                rd_data <= ram(to_integer(unsigned(rd_addr)));
            end if;
        end if;
    end process;
end bhv;


library ieee;
use ieee.std_logic_1164.all;

entity mux_2x1 is
	generic(
	width : positive
	);
	port(
		in0    : in  std_logic_vector(width-1 downto 0);
		in1    : in  std_logic_vector(width-1 downto 0);
		sel    : in  std_logic;
		output : out std_logic_vector(width-1 downto 0)
	);
end mux_2x1;

architecture bhv of mux_2x1 is
begin
	process(in0, in1, sel)
	begin
		if (sel = '1') then
			output <= in1;
		else
			output <= in0;
		end if;
	end process;
end bhv;


library ieee;
use ieee.std_logic_1164.all;

entity mux_4x1 is
	generic(
	width : positive
	);
	port(
		in0    : in  std_logic_vector(width-1 downto 0);
		in1    : in  std_logic_vector(width-1 downto 0);
		in2    : in  std_logic_vector(width-1 downto 0);
		in3    : in  std_logic_vector(width-1 downto 0);
		sel    : in  std_logic_vector(1 downto 0);
		output : out std_logic_vector(width-1 downto 0)
	);
end mux_4x1;

architecture bhv of mux_4x1 is
begin
	process(in0, in1, in2, in3, sel)
	begin
		if (sel = "11") then
			output <= in3;
		elsif (sel = "10") then
			output <= in2;
		elsif (sel = "01") then
			output <= in1;
		else
			output <= in0;
		end if;
	end process;
end bhv;


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- counter for incrementing ram address pointer
entity buffer_counter is
	port(
	en : in std_logic;
	clk    : in std_logic;
	rst    : in std_logic;
	output : out std_logic_vector(1 downto 0)
	);
end buffer_counter;

architecture bhv of buffer_counter is

	signal count : unsigned(1 downto 0);

begin
	process(clk, rst)
    begin
        if (rst = '1') then
            count  <= (others => '0');   
        elsif (rising_edge(clk)) then
            if (en = '1') then
                count  <= count + 1;
            end if;
        end if;
    end process;
	
	output <= std_logic_vector(count);
	
end bhv;

architecture main of cache is
	
	-- cache data out
	signal cache_out   : std_logic_vector(4*dwidth-1 downto 0);
	signal cache_data  : std_logic_vector(127 downto 0);
	signal data_buffer : std_logic_vector(127 downto 0);
	signal valid_bit   : std_logic_vector(0 downto 0);
	signal tag_cmp     : std_logic_vector(23 downto 0);
	
	-- cpu buffered inputs
	signal cpu_data_buffer_in    : std_logic_vector(dwidth-1 downto 0);
	signal cpu_address_buffer_in : std_logic_vector(dwidth-1 downto 0);
	
	-- ram controls
	signal ram_address_out : std_logic_vector(awidth-1 downto 0);
	signal ram_frame_in    : std_logic_vector(127 downto 0);
	signal ram_base_addr   : std_logic_vector(31 downto 0);
	signal ram_aout_clean  : std_logic_vector(31 downto 0); 
	signal output_buffer   : std_logic_vector(1 downto 0);
	
	-- FSM signals
	signal state       : std_logic_vector(3 downto 0);
	signal next_state  : std_logic_vector(3 downto 0);
	signal ram_sel     : std_logic;
	signal cache_hit   : std_logic;
	signal rd_en       : std_logic;
	signal wr_en       : std_logic;
	signal cpu_req     : std_logic;
	signal buffer_inc  : std_logic;
	signal buffer_clr  : std_logic;
	signal buffer_done : std_logic;
	signal ram_fill	   : std_logic;
	signal tag_match   : std_logic;

begin
	-- reads cpu inputs
	cpu_req <= cpu_read or cpu_write;
	
	-- fsm next state generator
	process(clk, rst)
	begin
		if rst = '1' then
			state <= "0000";
		elsif rising_edge(clk) then
			state <= next_state;
		end if;
	end process;
	
	-- fsm mealy control
	process(state, cpu_req, cpu_read, cache_hit, buffer_done)
	begin
    next_state <= state;
    case state is

        when "0000" =>
            if cpu_req = '1' then
                next_state <= "0001";
            end if;


        when "0001" =>
            if cpu_read = '1' then
                next_state <= "0010";
			else	
				next_state <= "0101";
            end if;


        when "0010" =>
            if cache_hit = '1' then
                next_state <= "0000";
			else
				next_state <= "0011";
            end if;


        when "0011" =>
			if buffer_done = '1' then
				next_state <= "0100";
			else
				next_state <= "0011";
			end if;


        when "0100" =>
            next_state <= "1000";


        when "0101" =>
            if cache_hit = '1' then
                next_state <= "1001";
			else
				next_state <= "0110";
            end if;


        when "0110" =>
            next_state <= "0011";
			
		when "0111" =>
            next_state <= "1000";
		
		when "1000" =>
			next_state <= "0000";
		
		when "1001" =>
			next_state <= "0000";
		
		when others =>
            null;
				
    end case;
	end process;	
	
	-- fsm state outputs
	process(state, cache_hit, cpu_data_buffer_in)
	begin

    rd_en 	   <= '0';
    wr_en 	   <= '0';
    ram_rd     <= '0';
	ram_wr		<= '0';
    buffer_inc <= '0';
	buffer_clr <= '0';
    cpu_stall  <= '0';
    req_done   <= '0';
	ram_fill   <= '0';
	ram_sel    <= '0';
	ram_dout   <= (others => '0');
	
    case state is

        when "0000" =>
            buffer_clr <= '1';


        when "0001" =>
            rd_en 	  <= '1';
			cpu_stall <= '1';


        when "0010" => 
			if cache_hit = '1' then
				req_done <= '1';
			else
				cpu_stall <= '1';
			end if;

        when "0011" => 
			cpu_stall  <= '1';
			ram_fill   <= '1';
			ram_rd 	   <= '1';
			ram_sel    <= '1';
			
			if buffer_done = '0' then
				buffer_inc <= '1';
			else
				buffer_inc <= '0';
			end if;

        when "0100" => 
            wr_en  <= '1';
			cpu_stall <= '1';

        when "0101" => 
			if (cache_hit = '1') then
				wr_en <= '1';
				req_done <= '1';
			else
				cpu_stall <= '1';
			end if;

        when "0110" => 
            cpu_stall <= '1';
				ram_dout  <= cpu_data_buffer_in;
				ram_wr    <= '1';
		
		when "0111" => 
            cpu_stall <= '1';
			rd_en     <= '1';
			
		when "1000" => 
            req_done   <= '1';
			buffer_clr <= '1';
			
		when "1001" =>
			req_done   <= '1';
			ram_wr     <= '1';
			
        when others =>
            null;
    end case;
	end process;
	
	-- cache write hit special case
	-- take current output, and splice in input word where needed
	process(cache_out, cpu_data_buffer_in, cpu_address_buffer_in)
	begin
		data_buffer <= cache_out;
		case cpu_address_buffer_in(1 downto 0) is
			when "00" =>
				data_buffer(31 downto 0) <= cpu_data_buffer_in;
			when "01" =>
				data_buffer(63 downto 32) <= cpu_data_buffer_in;
			when "10" =>
				data_buffer(95 downto 64) <= cpu_data_buffer_in;
			when "11" =>
				data_buffer(127 downto 96) <= cpu_data_buffer_in;
			when others =>
            null;
		end case;
	end process;
	
	-- cache data gets written to by both ram and cpu
	-- this mux selects between ram input data, and buffered cpu write in
	data_mux : entity work.mux_2x1
		generic map(
		width => 128
		)
		port map(
			in0    => data_buffer,
			in1    => ram_frame_in,
			sel    => ram_sel,
			output => cache_data
		);
	
	-- register input data
	data_buffer_in_cpu : entity work.buffer_reg
		generic map(
			dwidth => dwidth
		)
		port map(
			D   => cpu_din,
			Q   => cpu_data_buffer_in,
			en  => cpu_req,

			clk => clk,
			rst => rst
		);
		
	-- register input address
	address_buffer_in_cpu : entity work.buffer_reg
		generic map(
			dwidth => awidth
		)
		port map(
			D => cpu_ain,
			Q => cpu_address_buffer_in,
			en => cpu_req,

			clk => clk,
			rst => rst
		);
	
	-- inferred ram to hold tag
	tag_ram : entity work.general_ram
		generic map(
		awidth => 6,
		dwidth => 24
		)
		port map(
		clk     => clk,
		rd_en   => rd_en,
		rd_addr => cpu_address_buffer_in(7 downto 2),
		rd_data => tag_cmp,
		wr_en   => wr_en,
		wr_addr => cpu_address_buffer_in(7 downto 2), 
		wr_data => cpu_address_buffer_in(31 downto 8)
		);
		
	-- inferred ram to hold the valid bit
	validbit_ram : entity work.general_ram	
		generic map(
		awidth => 6,
		dwidth => 1
		)
		port map(
		clk     => clk,
		rd_en   => rd_en,
		rd_addr => cpu_address_buffer_in(7 downto 2),
		rd_data => valid_bit,
		wr_en   => wr_en,
		wr_addr => cpu_address_buffer_in(7 downto 2), 
		wr_data => "1"
		);
		
	-- compare tag held in ram with tag part of input address
	process(tag_cmp, cpu_address_buffer_in)
	begin
		if(tag_cmp = cpu_address_buffer_in(31 downto 8)) then
			tag_match <= '1';
		else
			tag_match <= '0';
		end if;
	end process;
	
	-- define a cache hit by the tags matching and valid bit being 1
	cache_hit <= valid_bit(0) and tag_match;
	
	-- inferred ram to hold data
	data_ram : entity work.general_ram
		generic map(
		awidth => 6,
		dwidth => 128
		)
		port map(
		clk     => clk,
		rd_en   => rd_en,
		rd_addr => cpu_address_buffer_in(7 downto 2),
		rd_data => cache_out,
		wr_en   => wr_en,
		wr_addr => cpu_address_buffer_in(7 downto 2), 
		wr_data => cache_data
		);
		
	-- use offset part of input address to select between the 4 32 bit words output
	-- by cache data ram
	cache_data_mux : entity work.mux_4x1
		generic map(
		width => 32
		)
		port map(
		in0 => cache_out(31 downto 0),
		in1 => cache_out(63 downto 32),
		in2 => cache_out(95 downto 64),
		in3 => cache_out(127 downto 96),
		sel => cpu_address_buffer_in(1 downto 0),
		output => cpu_dout
		);
		
	-- clear bottom 2 bits of input address to align for caching a full line from ram
	ram_base_addr <= cpu_address_buffer_in(31 downto 2) & "00";
		
	-- select between cpu address and address used for incrementing pointer
	-- on a cache write miss, the cpu first writes to external ram, so the ram needs
	-- access to the cpu address as well
	ram_addr_mux : entity work.mux_2x1
		generic map(
		width => 32
		)
		port map(
		in0 => cpu_address_buffer_in,
        in1 => ram_base_addr,
        sel => ram_sel,
        output => ram_aout_clean
		);
	
	-- instantiate counter for incrementing ram address pointer
	counter : entity work.buffer_counter
		port map(
		en     => buffer_inc,
		clk    => clk,
		rst    => buffer_clr,
		output =>  output_buffer
		);
	
	-- offset for ram pointer onlys need to go from 00 to 11, since a cache line
	-- is 4 words
	buffer_done <= output_buffer(0) and output_buffer(1);
	
	-- incremement base pointer (or add 0 to cpu address)
	ram_aout <= std_logic_vector(unsigned(ram_aout_clean) + unsigned(output_buffer));
	
	-- shift ram data in 32 bits at a time to fill the full 128 bit cache line
	process(clk, rst)
	begin
    if rst = '1' then
        ram_frame_in <= (others => '0');

    elsif rising_edge(clk) then
        if ram_fill = '1' then
            case output_buffer is
                when "00" =>
                    ram_frame_in(31 downto 0) <= ram_din;

                when "01" =>
                    ram_frame_in(63 downto 32) <= ram_din;

                when "10" =>
                    ram_frame_in(95 downto 64) <= ram_din;

                when "11" =>
                    ram_frame_in(127 downto 96) <= ram_din;

                when others =>
                    null;
            end case;
        end if;
    end if;
	end process;
	
end main;
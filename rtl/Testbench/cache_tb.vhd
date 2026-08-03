library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache_tb is
end cache_tb;

architecture sim of cache_tb is

    constant AWIDTH : positive := 32;
    constant DWIDTH : positive := 32;

    signal clk  : std_logic := '0';
    signal rst  : std_logic := '1';

    signal cpu_ain   : std_logic_vector(AWIDTH-1 downto 0) := (others => '0');
	signal cpu_din   : std_logic_vector(DWIDTH-1 downto 0) := (others => '0');
	signal cpu_dout  : std_logic_vector(DWIDTH-1 downto 0);

	signal cpu_read  : std_logic := '0';
	signal cpu_write : std_logic := '0';

	signal cpu_stall : std_logic;
	signal req_done  : std_logic;

	signal ram_din   : std_logic_vector(31 downto 0) := (others => '0');
	signal ram_dout  : std_logic_vector(31 downto 0);
	signal ram_aout  : std_logic_vector(31 downto 0);
	signal ram_rd    : std_logic;
	signal ram_wr    : std_logic;

begin

    --------------------------------------------------------------------
    -- DUT
    --------------------------------------------------------------------

    DUT : entity work.cache
        port map(
            cpu_ain => cpu_ain,
            cpu_din => cpu_din,
            cpu_read => cpu_read,
            cpu_write => cpu_write,

            clk => clk,
            rst => rst,

            ram_din => ram_din,
            ram_dout => ram_dout,

            cpu_dout => cpu_dout,
            cpu_stall => cpu_stall,
            req_done => req_done,

            ram_aout => ram_aout,
            ram_rd => ram_rd,
            ram_wr => ram_wr
        );

    --------------------------------------------------------------------
    -- Clock
    --------------------------------------------------------------------

    clk <= not clk after 5 ns;

    --------------------------------------------------------------------
    -- Empty RAM
    --------------------------------------------------------------------

    ram_din <= (others => '0');

    --------------------------------------------------------------------
    -- Stimulus
    --------------------------------------------------------------------

    process
    begin
        cpu_read  <= '0';
        cpu_write <= '0';
        cpu_ain   <= (others => '0');
        cpu_din   <= (others => '0');

        ------------------------------------------------------------
        -- Reset
        ------------------------------------------------------------

        rst <= '1';
        wait for 20 ns;
        rst <= '0';
        wait for 20 ns;

        ------------------------------------------------------------
        -- Initial miss (bring address 0-3 into cache)
        ------------------------------------------------------------

        cpu_ain  <= x"00000000";
		cpu_read <= '1';

		wait until req_done='1';

		cpu_read <= '0';

        ------------------------------------------------------------
        -- Write address 0
        ------------------------------------------------------------

        cpu_ain   <= x"00000000";
		cpu_din   <= x"11111111";
		cpu_write <= '1';

		wait until req_done='1';

		cpu_write <= '0';

        ------------------------------------------------------------
        -- Write address 1
        ------------------------------------------------------------

        cpu_ain   <= x"00000001";
        cpu_din   <= x"22222222";
        cpu_write <= '1';

        wait until req_done='1';

        cpu_write <= '0';


        ------------------------------------------------------------
        -- Write address 2
        ------------------------------------------------------------

        cpu_ain   <= x"00000002";
        cpu_din   <= x"33333333";
        cpu_write <= '1';

        wait until req_done='1';

        cpu_write <= '0';

        ------------------------------------------------------------
        -- Write address 3
        ------------------------------------------------------------

        cpu_ain   <= x"00000003";
        cpu_din   <= x"44444444";
        cpu_write <= '1';

        wait until req_done='1';

        cpu_write <= '0';

        ------------------------------------------------------------
        -- Read address 0
        ------------------------------------------------------------

        cpu_ain  <= x"00000000";
        cpu_read <= '1';

        wait until req_done='1';

        assert cpu_dout = x"11111111"
            report "Address 0 incorrect"
            severity error;

        cpu_read <= '0';

        ------------------------------------------------------------
        -- Read address 1
        ------------------------------------------------------------

        cpu_ain  <= x"00000001";
        cpu_read <= '1';

        wait until req_done='1';

        assert cpu_dout = x"22222222"
            report "Address 1 incorrect"
            severity error;

        cpu_read <= '0';

        ------------------------------------------------------------
        -- Read address 2
        ------------------------------------------------------------

        cpu_ain  <= x"00000002";
        cpu_read <= '1';

        wait until req_done='1';

        assert cpu_dout = x"33333333"
            report "Address 2 incorrect"
            severity error;

        cpu_read <= '0';

        ------------------------------------------------------------
        -- Read address 3
        ------------------------------------------------------------

        cpu_ain  <= x"00000003";
        cpu_read <= '1';

        wait until req_done='1';

        assert cpu_dout = x"44444444"
            report "Address 3 incorrect"
            severity error;

        cpu_read <= '0';

        report "TEST PASSED" severity note;

        wait;

    end process;

end sim;
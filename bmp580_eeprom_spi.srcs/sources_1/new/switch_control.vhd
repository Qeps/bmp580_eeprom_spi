library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity switch_control is
    port ( 
        clk          : in  std_logic;
        switch_input : in  std_logic;
        rst_l        : out std_logic;
        start        : out std_logic
    );
end switch_control;

architecture rtl of switch_control is

    signal switch_sync_1 : std_logic := '0';
    signal switch_sync_2 : std_logic := '0';

    signal start_reg : std_logic := '0';
    signal rst_l_reg : std_logic := '0';

begin

    -- 2FF synchronizer
    process(clk)
    begin
        if rising_edge(clk) then
            switch_sync_1 <= switch_input;
            switch_sync_2 <= switch_sync_1;
        end if;
    end process;

    -- debounce + control
    process(clk)
        variable cnt : unsigned(18 downto 0) := (others => '0');
    begin
        if rising_edge(clk) then

            if switch_sync_2 = '0' then
                cnt := (others => '0');
                start_reg <= '0';
                rst_l_reg <= '0';

            else
                if cnt < 500000 then  -- 5 ms - 100 MHz
                    cnt := cnt + 1;
                    start_reg <= '0';
                    rst_l_reg <= '0';
                else
                    start_reg <= '1';
                    rst_l_reg <= '1';
                end if;
            end if;

        end if;
    end process;

    start <= start_reg;
    rst_l <= rst_l_reg;

end rtl;
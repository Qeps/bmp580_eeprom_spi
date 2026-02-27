library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity led_control is
    Port ( 
        clk      : in STD_LOGIC;
        rst_l    : in STD_LOGIC;
        start    : in STD_LOGIC;
        led_ctrl : out STD_LOGIC
    );
end led_control;

architecture rtl of led_control is
    signal led_ctrl_reg : std_logic := '0';
begin
    process (clk)
        variable led_cnt : unsigned (27 downto 0) := (others => '0');
    begin
        if rising_edge (clk) then
            if rst_l = '0' then
                led_cnt      := (others => '0');
                led_ctrl_reg <= '0';
            elsif start = '1' then 
                if led_cnt < 100000000 - 1 then
                    led_cnt      := led_cnt + 1;
                else
                    led_cnt      := (others => '0');
                    led_ctrl_reg <= not led_ctrl_reg;
                end if;
            else
                led_cnt      := (others => '0');
                led_ctrl_reg <= '0';
            end if;
         end if;
    end process;
    
    led_ctrl <= led_ctrl_reg;
end rtl;

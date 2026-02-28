library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity bmp580_control is
    port (
        clk           : in std_logic;
        rst_l         : in std_logic;
        
        tx_ready      : in std_logic;
        rx_count      : in std_logic_vector(7 downto 0);
        rx_data_valid : in std_logic;
        rx_byte       : in std_logic_vector(7 downto 0);
        
        tx_count      : out std_logic_vector(7 downto 0);
        tx_byte       : out std_logic_vector(7 downto 0);
        tx_data_valid : out std_logic;
        
        temp_data_valid : out std_logic;
        temp_raw_data   : out std_logic_vector(23 downto 0);
        
        test_ok : out std_logic
    );
end bmp580_control;

architecture rtl of bmp580_control is
    constant DUMMY_BYTE        : std_logic_vector(7 downto 0) := x"00";
    constant READ_DATA         : std_logic_vector(7 downto 0) := x"80";
    constant CHIP_ID_ADDR      : std_logic_vector(7 downto 0) := x"01"; -- reset value: x"50"
    constant INIT_DELAY_CYCLES : integer := 200000; -- 2 ms @ 100 MHz

    type state_t is (
        IDLE,
        WAIT_INIT_2MS,
        INIT_SEND_DUMMY1,
        INIT_WAIT_DUMMY1_RX,
        INIT_SEND_DUMMY2,
        INIT_WAIT_DUMMY2_RX,
        READ_SEND_ADDR,
        READ_WAIT_ADDR_RX,
        READ_SEND_DUMMY,
        READ_WAIT_DATA_RX,
        DONE
    );

    signal state               : state_t := IDLE;
    signal tx_count_reg        : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_byte_reg         : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_data_valid_reg   : std_logic := '0';
    signal temp_data_valid_reg : std_logic := '0';
    signal temp_raw_data_reg   : std_logic_vector(23 downto 0) := (others => '0');
    signal init_delay_cnt      : unsigned(17 downto 0) := (others => '0');
    signal chip_ok_reg         : std_logic := '0';
begin
    test_ok <= chip_ok_reg;
    tx_count        <= tx_count_reg;
    tx_byte         <= tx_byte_reg;
    tx_data_valid   <= tx_data_valid_reg;
    temp_data_valid <= temp_data_valid_reg;
    temp_raw_data   <= temp_raw_data_reg;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_l = '0' then
                tx_count_reg        <= (others => '0');
                tx_byte_reg         <= (others => '0');
                tx_data_valid_reg   <= '0';
                temp_data_valid_reg <= '0';
                temp_raw_data_reg   <= (others => '0');
                init_delay_cnt      <= (others => '0');
                chip_ok_reg         <= '0';
                state               <= IDLE;
            else
                tx_data_valid_reg   <= '0';
                temp_data_valid_reg <= '0';

                case state is
                    when IDLE =>
                        tx_count_reg      <= (others => '0');
                        tx_byte_reg       <= (others => '0');
                        temp_raw_data_reg <= (others => '0');
                        init_delay_cnt    <= (others => '0');
                        chip_ok_reg       <= '0';
                        state             <= WAIT_INIT_2MS;

                    when WAIT_INIT_2MS =>
                        if init_delay_cnt < to_unsigned(INIT_DELAY_CYCLES - 1, init_delay_cnt'length) then
                            init_delay_cnt <= init_delay_cnt + 1;
                        else
                            init_delay_cnt <= (others => '0');
                            state          <= INIT_SEND_DUMMY1;
                        end if;

                    -- Force BMP580 to SPI mode by two dummy bytes under one CS
                    when INIT_SEND_DUMMY1 =>
                        if tx_ready = '1' then
                            tx_count_reg      <= x"02";
                            tx_byte_reg       <= DUMMY_BYTE;
                            tx_data_valid_reg <= '1';
                            state             <= INIT_WAIT_DUMMY1_RX;
                        end if;

                    when INIT_WAIT_DUMMY1_RX =>
                        if rx_data_valid = '1' then
                            state <= INIT_SEND_DUMMY2;
                        end if;

                    when INIT_SEND_DUMMY2 =>
                        if tx_ready = '1' then
                            tx_byte_reg       <= DUMMY_BYTE;
                            tx_data_valid_reg <= '1';
                            state             <= INIT_WAIT_DUMMY2_RX;
                        end if;

                    when INIT_WAIT_DUMMY2_RX =>
                        if rx_data_valid = '1' then
                            state <= READ_SEND_ADDR;
                        end if;

                    when READ_SEND_ADDR =>
                        if tx_ready = '1' then
                            tx_count_reg      <= x"02";
                            tx_byte_reg       <= CHIP_ID_ADDR or READ_DATA;
                            tx_data_valid_reg <= '1';
                            state             <= READ_WAIT_ADDR_RX;
                        end if;

                    when READ_WAIT_ADDR_RX =>
                        if rx_data_valid = '1' then
                            state <= READ_SEND_DUMMY;
                        end if;

                    when READ_SEND_DUMMY =>
                        if tx_ready = '1' then
                            tx_byte_reg       <= DUMMY_BYTE;
                            tx_data_valid_reg <= '1';
                            state             <= READ_WAIT_DATA_RX;
                        end if;

                    when READ_WAIT_DATA_RX =>
                        if rx_data_valid = '1' then
                            if rx_byte = x"50" then
                                chip_ok_reg <= '1';
                            else
                                chip_ok_reg <= '0';
                            end if;
                            state <= DONE;
                        end if;

                    when DONE =>
                        null;
                end case;
            end if;
        end if;
    end process;
end rtl;

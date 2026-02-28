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
        
        spi_ready : out std_logic
    );
end bmp580_control;

architecture rtl of bmp580_control is
    constant DUMMY_BYTE        : std_logic_vector(7 downto 0) := x"00";
    constant READ_DATA         : std_logic_vector(7 downto 0) := x"80";
    constant CHIP_ID_ADDR      : std_logic_vector(7 downto 0) := x"01"; -- reset value: x"50"
    constant STATUS_ADDR       : std_logic_vector(7 downto 0) := x"28"; -- reset value: x"02"
    constant INT_STATUS        : std_logic_vector(7 downto 0) := x"28"; -- reset value: x"00"
    constant INIT_DELAY_CYCLES : integer := 200000; -- 2 ms @ 100 MHz

    type rx_wait_ctx_t is (
        NONE,
        INIT_WAIT_DUMMY1_RX,
        INIT_WAIT_DUMMY2_RX,
        READ_WAIT_CHIP_ID_ADDR_RX,
        READ_WAIT_STATUS_ADDR_RX,
        READ_WAIT_INT_STATUS_ADDR_RX
    );

    type state_t is (
        IDLE,
        WAIT_RX,

        -- 1. Wait 2ms - power-up time - doc. 4.3.9
        WAIT_INIT_2MS,

        -- 2. Initialize SPI interface - doc. 5.1 Protocol Selection
        INIT_SEND_DUMMY1,
        INIT_SEND_DUMMY2,

        -- 3. Recomemended steps AFTER power up - doc. 4.3.9:
        --      a) Read out the CHIP_ID register and check that it is not all 0
        READ_SEND_CHIP_ID_ADDR,
        READ_SEND_CHIP_ID_DUMMY,
        READ_WAIT_CHIP_ID_DATA_RX,
        --      b) Read out the STATUS register and check that status_nvm == 1, status_nvm_err == 0;
        READ_SEND_STATUS_ADDR,
        READ_SEND_STATUS_DUMMY,
        READ_WAIT_STATUS_DATA_RX
        --      c) Read out the INT_STATUS.por register field and check that it is set to 1; that means INT_STATUS == 0x01
        -- READ_SEND_INT_STATUS_ADDR,
        -- READ_SEND_INT_STATUS_DUMMY,
        -- READ_WAIT_INT_STATUS_DATA_RX

        -- 4. Set mode to STANDBY - some registers cannot be changed in other modes - doc. 4.3.7 and 4.3.8
    );

    signal state               : state_t := IDLE;
    signal rx_wait_ctx         : rx_wait_ctx_t := NONE;
    signal tx_count_reg        : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_byte_reg         : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_data_valid_reg   : std_logic := '0';
    signal temp_data_valid_reg : std_logic := '0';
    signal temp_raw_data_reg   : std_logic_vector(23 downto 0) := (others => '0');
    signal init_delay_cnt      : unsigned(17 downto 0) := (others => '0');
    signal spi_ready_reg       : std_logic := '0';
begin
    spi_ready       <= spi_ready_reg;
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
                spi_ready_reg       <= '0';
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
                        rx_wait_ctx       <= NONE;
                        spi_ready_reg     <= '0';
                        state             <= WAIT_INIT_2MS;
                    
                    when WAIT_RX =>
                        if rx_data_valid = '1' then
                            case rx_wait_ctx is
                                when INIT_WAIT_DUMMY1_RX =>
                                    state <= INIT_SEND_DUMMY2;
                                when INIT_WAIT_DUMMY2_RX =>
                                    state <= READ_SEND_CHIP_ID_ADDR;
                                when READ_WAIT_CHIP_ID_ADDR_RX =>
                                    state <= READ_SEND_CHIP_ID_DUMMY;
                                when READ_WAIT_STATUS_ADDR_RX =>
                                    state <= READ_SEND_STATUS_DUMMY;
                                when OTHERS =>
                                    state <= IDLE;
                            end case;
                        end if;

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
                            rx_wait_ctx       <= INIT_WAIT_DUMMY1_RX;
                            state             <= WAIT_RX;
                        end if;

                    when INIT_SEND_DUMMY2 =>
                        if tx_ready = '1' then
                            tx_byte_reg       <= DUMMY_BYTE;
                            tx_data_valid_reg <= '1';
                            rx_wait_ctx       <= INIT_WAIT_DUMMY2_RX;
                            state             <= WAIT_RX;
                        end if;

                    -- 2.a
                    when READ_SEND_CHIP_ID_ADDR =>
                        if tx_ready = '1' then
                            tx_count_reg      <= x"02";
                            tx_byte_reg       <= CHIP_ID_ADDR or READ_DATA;
                            tx_data_valid_reg <= '1';
                            rx_wait_ctx       <= READ_WAIT_CHIP_ID_ADDR_RX;
                            state             <= WAIT_RX;
                        end if;

                    when READ_SEND_CHIP_ID_DUMMY =>
                        if tx_ready = '1' then
                            tx_byte_reg       <= DUMMY_BYTE;
                            tx_data_valid_reg <= '1';
                            state             <= READ_WAIT_CHIP_ID_DATA_RX;
                        end if;

                    when READ_WAIT_CHIP_ID_DATA_RX =>
                        if rx_data_valid = '1' then
                            if rx_byte = x"50" then
                                -- spi_ready_reg <= '1';
                                state         <= READ_SEND_STATUS_ADDR;
                            else
                                state <= IDLE;
                            end if;
                        end if;
                    
                    -- 2.b
                    when READ_SEND_STATUS_ADDR =>
                        if tx_ready = '1' then
                            tx_count_reg      <= x"02";
                            tx_byte_reg       <= STATUS_ADDR or READ_DATA;
                            tx_data_valid_reg <= '1';
                            rx_wait_ctx       <= READ_WAIT_STATUS_ADDR_RX;
                            state             <= WAIT_RX;
                        end if;
                    
                    when READ_SEND_STATUS_DUMMY =>
                        if tx_ready = '1' then
                            tx_byte_reg       <= DUMMY_BYTE;
                            tx_data_valid_reg <= '1';
                            state             <= READ_WAIT_STATUS_DATA_RX;
                        end if;

                    when READ_WAIT_STATUS_DATA_RX =>
                        if rx_data_valid = '1' then
                            if rx_byte(2 downto 1) = "01" then
                                spi_ready_reg <= '1';
                            else
                                spi_ready_reg <= '1';
                            end if;
                        end if;

                    when OTHERS =>
                        tx_count_reg        <= (others => '0');
                        tx_byte_reg         <= (others => '0');
                        tx_data_valid_reg   <= '0';
                        temp_data_valid_reg <= '0';
                        temp_raw_data_reg   <= (others => '0');
                        init_delay_cnt      <= (others => '0');
                        spi_ready_reg       <= '0';
                        rx_wait_ctx         <= NONE;
                        state               <= IDLE;
                end case;
            end if;
        end if;
    end process;
end rtl;

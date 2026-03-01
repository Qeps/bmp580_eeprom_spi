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
    constant DUMMY_BYTE           : std_logic_vector(7 downto 0) := x"00";
    constant READ_DATA            : std_logic_vector(7 downto 0) := x"80";

    constant CHIP_ID_ADDR         : std_logic_vector(7 downto 0) := x"01"; -- reset value: x"50"

    constant STATUS_ADDR          : std_logic_vector(7 downto 0) := x"28"; -- reset value: x"02"

    constant INT_STATUS_ADDR      : std_logic_vector(7 downto 0) := x"27"; -- reset value: x"00"

    constant ODR_CONFIG_ADDR      : std_logic_vector(7 downto 0) := x"37"; -- reset value: x"70"
    constant DEEP_DIS_DEFAULT     : std_logic                    := '0';
    constant ODR_DEFAULT          : std_logic_vector(4 downto 0) := "11100";
    constant PWR_STANDBY          : std_logic_vector(1 downto 0) := "00";
    constant PWR_NORMAL           : std_logic_vector(1 downto 0) := "01";
    constant CFG_STANDBY          : std_logic_vector(7 downto 0) := DEEP_DIS_DEFAULT & ODR_DEFAULT & PWR_STANDBY; -- x"70"
    constant CFG_NORMAL           : std_logic_vector(7 downto 0) := DEEP_DIS_DEFAULT & ODR_DEFAULT & PWR_NORMAL;  -- x"71"

    constant OSR_CONFIG_ADDR      : std_logic_vector(7 downto 0) := x"36";
    constant RSVD7_ZERO           : std_logic := '0';
    constant PRESS_DISABLE        : std_logic := '0';
    constant PRESS_ENABLE         : std_logic := '1';
    constant OSR_1X               : std_logic_vector(2 downto 0) := "000";
    constant OSR_2X               : std_logic_vector(2 downto 0) := "001";
    constant OSR_4X               : std_logic_vector(2 downto 0) := "010";
    constant OSR_8X               : std_logic_vector(2 downto 0) := "011";
    constant OSR_16X              : std_logic_vector(2 downto 0) := "100";
    constant OSR_32X              : std_logic_vector(2 downto 0) := "101";
    constant OSR_64X              : std_logic_vector(2 downto 0) := "110";
    constant OSR_128X             : std_logic_vector(2 downto 0) := "111";
    constant CFG_OSR_TEMP_ONLY    : std_logic_vector(7 downto 0) := RSVD7_ZERO & PRESS_DISABLE & OSR_1X & OSR_8X; -- x"03" Temp only: osr_t=8x, press_en=0
    constant CFG_OSR_PT_8X        : std_logic_vector(7 downto 0) := RSVD7_ZERO & PRESS_ENABLE & OSR_8X & OSR_8X;  -- x"5B"


    constant INIT_DELAY_CYCLES    : integer                      := 200000; -- 2   ms @ 100 MHz
    constant STANDBY_DELAY_CYCLES : integer                      := 250000; -- 2.5 ms @ 100 MHz
    constant NORMAL_DELAY_CYCLES  : integer                      := 400000; -- 4   ms @ 100 MHz

    type rx_wait_ctx_t is (
        NONE,
        INIT_WAIT_DUMMY1_RX,
        INIT_WAIT_DUMMY2_RX,
        READ_WAIT_CHIP_ID_ADDR_RX,
        READ_WAIT_STATUS_ADDR_RX,
        READ_WAIT_INT_STATUS_ADDR_RX,
        SET_SEND_ODR_CONFIG_ADDR_RX,
        READ_WAIT_ODR_CONFIG_ADDR_RX,
        SET_SEND_OSR_CONFIG_ADDR_RX,
        SET_SEND_ODR_CONFIG_ADDR_RX2
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
        READ_SEND_CHIP_ID_DUMMY, -- w jeden
        READ_WAIT_CHIP_ID_DATA_RX,
        --      b) Read out the STATUS register and check that status_nvm == 1, status_nvm_err == 0;
        READ_SEND_STATUS_ADDR,
        READ_SEND_STATUS_DUMMY, -- w jeden
        READ_WAIT_STATUS_DATA_RX,
        --      c) Read out the INT_STATUS.por register field and check that it is set to 1; that means INT_STATUS == 0x10
        READ_SEND_INT_STATUS_ADDR,
        READ_SEND_INT_STATUS_DUMMY, -- w jeden
        READ_WAIT_INT_STATUS_DATA_RX,

        -- 4. Set mode to STANDBY and check value - some registers cannot be changed in other modes - doc. 4.3.7 and 4.3.8
        --      ODR pwr_mode (first two bits):
        --          00 - STANDBY
        --          01 - NORMAL
        --          10 - FORCED
        --          11 - NON_STOP
        SET_SEND_ODR_CONFIG_ADDR,
        SET_SEND_ODR_CONFIG_DATA,
        -- Check if it set correct - tstandby = 2.5ms, time from any mode to STANDBY
        WAIT_T_STANDBY_MS,
        READ_SEND_ODR_CONFIG_ADDR,
        READ_SEND_ODR_CONFIG_DUMMY,
        READ_WAIT_ODR_CONFIG_DATA_RX,

        -- 5. Set OSR first and ODR to normal mode for proper oversampling handle
        --      a) OSR - (0x36 = 0x03 (press_en=0, osr_t=8x))
        SET_SEND_OSR_CONFIG_ADDR,
        SET_SEND_OSR_CONFIG_DATA,
        --      b) ODR - (deep_dis=0, odr=1Hz, pwr_mode=01)
        SET_SEND_ODR_CONFIG_ADDR2, -- send odr register addr once again
        SET_SEND_ODR_CONFIG_DATA2, -- send odr register data to match OSR CONFIG
        WAIT_T_NORMAL_MS           -- wait treconf_deep 4ms - doc. Electrical characteristics

        -- 6. READ OSR and ODR registers to confirm correct configuratation
    );

    signal state               : state_t                       := IDLE;
    signal rx_wait_ctx         : rx_wait_ctx_t                 := NONE;
    signal tx_count_reg        : std_logic_vector(7 downto 0)  := (others => '0');
    signal tx_byte_reg         : std_logic_vector(7 downto 0)  := (others => '0');
    signal tx_data_valid_reg   : std_logic                     := '0';
    signal temp_data_valid_reg : std_logic                     := '0';
    signal temp_raw_data_reg   : std_logic_vector(23 downto 0) := (others => '0');
    signal init_delay_cnt      : unsigned(17 downto 0)         := (others => '0');
    signal standby_delay_cnt   : unsigned(17 downto 0)         := (others => '0');
    signal normal_delay_cnt    : unsigned(17 downto 0)         := (others => '0');
    signal spi_ready_reg       : std_logic                     := '0';
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
                standby_delay_cnt   <= (others => '0');
                normal_delay_cnt    <= (others => '0');
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
                        standby_delay_cnt <= (others => '0');
                        normal_delay_cnt  <= (others => '0');
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

                                when READ_WAIT_INT_STATUS_ADDR_RX =>
                                    state <= READ_SEND_INT_STATUS_DUMMY;

                                when SET_SEND_ODR_CONFIG_ADDR_RX =>
                                    state <= SET_SEND_ODR_CONFIG_DATA;
                                
                                when READ_WAIT_ODR_CONFIG_ADDR_RX =>
                                    state <= READ_SEND_ODR_CONFIG_DUMMY;
                                
                                when SET_SEND_OSR_CONFIG_ADDR_RX =>
                                    state <= SET_SEND_OSR_CONFIG_DATA;

                                when SET_SEND_ODR_CONFIG_ADDR_RX2=>
                                    state <= SET_SEND_ODR_CONFIG_DATA2;

                                when OTHERS =>
                                    state <= IDLE;
                            end case;
                        end if;

                    -- 1.                
                    when WAIT_INIT_2MS =>
                        if init_delay_cnt < to_unsigned(INIT_DELAY_CYCLES - 1, init_delay_cnt'length) then
                            init_delay_cnt <= init_delay_cnt + 1;
                        else
                            init_delay_cnt <= (others => '0');
                            state          <= INIT_SEND_DUMMY1;
                        end if;

                    -- 2. Force BMP580 to SPI mode by two dummy bytes under one CS
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

                    -- 3.a
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
                                -- spi_ready_reg <= '1'; -- UNCOMMENT
                                state         <= READ_SEND_STATUS_ADDR;
                            else
                                state <= IDLE;
                            end if;
                        end if;
                    
                    -- 3.b
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
                                state <= READ_SEND_INT_STATUS_ADDR;
                            else
                                state <= IDLE;
                            end if;
                        end if;
                    
                    -- 3.c
                    when READ_SEND_INT_STATUS_ADDR =>
                        if tx_ready = '1' then
                            tx_count_reg      <= x"02";
                            tx_byte_reg       <= INT_STATUS_ADDR or READ_DATA;
                            tx_data_valid_reg <= '1';
                            rx_wait_ctx       <= READ_WAIT_INT_STATUS_ADDR_RX;
                            state             <= WAIT_RX;
                        end if;
                    
                    when READ_SEND_INT_STATUS_DUMMY =>
                        if tx_ready = '1' then
                            tx_byte_reg       <= DUMMY_BYTE;
                            tx_data_valid_reg <= '1';
                            state             <= READ_WAIT_INT_STATUS_DATA_RX;
                        end if;
                    
                    when READ_WAIT_INT_STATUS_DATA_RX =>
                        if rx_data_valid = '1' then
                            if rx_byte = x"10" then
                                state <= SET_SEND_ODR_CONFIG_ADDR;
                            else
                                state <= IDLE;
                            end if;
                        end if; 
                    
                    -- 4.
                    when SET_SEND_ODR_CONFIG_ADDR =>
                        if tx_ready = '1' then
                            tx_count_reg      <= x"02";
                            tx_byte_reg       <= ODR_CONFIG_ADDR;
                            tx_data_valid_reg <= '1';
                            rx_wait_ctx       <= SET_SEND_ODR_CONFIG_ADDR_RX;
                            state             <= WAIT_RX;
                        end if;

                    when SET_SEND_ODR_CONFIG_DATA =>
                        if tx_ready = '1' then
                            tx_byte_reg       <= CFG_STANDBY;
                            tx_data_valid_reg <= '1';
                            state             <= WAIT_T_STANDBY_MS;
                        end if;

                    when WAIT_T_STANDBY_MS =>
                        if standby_delay_cnt < to_unsigned(STANDBY_DELAY_CYCLES - 1, standby_delay_cnt'length) then
                            standby_delay_cnt <= standby_delay_cnt + 1;
                        else
                            standby_delay_cnt <= (others => '0');
                            state          <= READ_SEND_ODR_CONFIG_ADDR;
                        end if;
                    
                    when READ_SEND_ODR_CONFIG_ADDR =>
                        if tx_ready = '1' then
                            tx_count_reg      <= x"02";
                            tx_byte_reg       <= ODR_CONFIG_ADDR or READ_DATA;
                            tx_data_valid_reg <= '1';
                            rx_wait_ctx       <= READ_WAIT_ODR_CONFIG_ADDR_RX;
                            state             <= WAIT_RX;
                        end if;
                    
                    when READ_SEND_ODR_CONFIG_DUMMY =>
                        if tx_ready = '1' then
                            tx_byte_reg       <= DUMMY_BYTE;
                            tx_data_valid_reg <= '1';
                            state             <= READ_WAIT_ODR_CONFIG_DATA_RX;
                        end if;
                    
                    when READ_WAIT_ODR_CONFIG_DATA_RX =>
                        if rx_data_valid = '1' then
                            if rx_byte = CFG_STANDBY then
                                state <= SET_SEND_OSR_CONFIG_ADDR;
                            else
                                state <= IDLE;
                            end if;
                        end if; 
                    
                    -- 5.
                    when SET_SEND_OSR_CONFIG_ADDR =>
                        if tx_ready = '1' then
                            tx_count_reg      <= x"02";
                            tx_byte_reg       <= OSR_CONFIG_ADDR;
                            tx_data_valid_reg <= '1';
                            rx_wait_ctx       <= SET_SEND_OSR_CONFIG_ADDR_RX;
                            state             <= WAIT_RX;
                        end if;
                    
                    when SET_SEND_OSR_CONFIG_DATA =>
                        if tx_ready = '1' then
                            tx_byte_reg       <= CFG_OSR_TEMP_ONLY;
                            tx_data_valid_reg <= '1';
                            state             <= SET_SEND_ODR_CONFIG_ADDR2;
                        end if;

                    when SET_SEND_ODR_CONFIG_ADDR2 =>
                        if tx_ready = '1' then
                            tx_count_reg      <= x"02";
                            tx_byte_reg       <= ODR_CONFIG_ADDR;
                            tx_data_valid_reg <= '1';
                            rx_wait_ctx       <= SET_SEND_ODR_CONFIG_ADDR_RX2;
                            state             <= WAIT_RX;
                        end if;
                    
                    when SET_SEND_ODR_CONFIG_DATA2 =>
                        if tx_ready = '1' then
                            tx_byte_reg       <= CFG_NORMAL;
                            tx_data_valid_reg <= '1';
                            state             <= WAIT_T_NORMAL_MS;
                        end if;

                    when WAIT_T_NORMAL_MS =>
                        if normal_delay_cnt < to_unsigned(NORMAL_DELAY_CYCLES - 1, normal_delay_cnt'length) then
                            normal_delay_cnt <= normal_delay_cnt + 1;
                        else
                            normal_delay_cnt <= (others => '0');
                            state            <= IDLE;
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

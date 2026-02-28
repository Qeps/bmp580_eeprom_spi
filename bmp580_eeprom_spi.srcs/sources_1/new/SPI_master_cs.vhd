library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SPI_master_cs is
    generic (
        SPI_MODE          : integer := 0;
        CLKS_PER_HALF_BIT : integer := 2;
        MAX_BYTES_PER_CS  : integer := 2;
        CS_INACTIVE_CLKS  : integer := 1
    );
    port (
        rst_l : in std_logic;
        clk   : in std_logic;

        -- TX
        tx_count      : in  unsigned(7 downto 0);
        tx_byte       : in  std_logic_vector(7 downto 0);
        tx_data_valid : in  std_logic;
        tx_ready      : out std_logic;

        -- RX
        rx_count      : out unsigned(7 downto 0);
        rx_data_valid : out std_logic;
        rx_byte       : out std_logic_vector(7 downto 0);

        -- SPI
        spi_clk  : out std_logic;
        spi_miso : in  std_logic;
        spi_mosi : out std_logic;
        spi_cs_n : out std_logic
    );
end entity;

architecture RTL of SPI_master_cs is
    type state_t is (IDLE, TRANSFER, CS_INACTIVE);

    signal state_reg : state_t;
    signal cs_active_reg       : std_logic;
    signal cs_inactive_cnt_reg : integer range 0 to CS_INACTIVE_CLKS;
    signal tx_count_reg        : integer range 0 to MAX_BYTES_PER_CS;
    signal master_ready        : std_logic;
    signal rx_count_reg        : unsigned(7 downto 0);
    signal rx_data_valid_int   : std_logic;
    signal rx_byte_int         : std_logic_vector(7 downto 0);
begin

    --------------------------------------------------------------------------
    -- Core SPI
    --------------------------------------------------------------------------
    SPI_Core : entity work.SPI_Master
        generic map (
            SPI_MODE          => SPI_MODE,
            CLKS_PER_HALF_BIT => CLKS_PER_HALF_BIT
        )
        port map (
            rst_l         => rst_l,
            clk           => clk,
            tx_byte       => tx_byte,
            tx_data_valid => tx_data_valid,
            tx_ready      => master_ready,
            rx_data_valid => rx_data_valid_int,
            rx_byte       => rx_byte_int,
            spi_clk       => spi_clk,
            spi_miso      => spi_miso,
            spi_mosi      => spi_mosi
        );

    --------------------------------------------------------------------------
    -- CS state machine
    --------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then

            if rst_l = '0' then
                state_reg           <= IDLE;
                cs_active_reg       <= '0';
                tx_count_reg        <= 0;
                cs_inactive_cnt_reg <= CS_INACTIVE_CLKS;

            else

                case state_reg is

                    when IDLE =>
                        if tx_data_valid = '1' then
                            cs_active_reg <= '1';
                            tx_count_reg  <= to_integer(tx_count) - 1;
                            state_reg     <= TRANSFER;
                        end if;

                    when TRANSFER =>
                        if master_ready = '1' then
                            if tx_count_reg > 0 then
                                if tx_data_valid = '1' then
                                    tx_count_reg <= tx_count_reg - 1;
                                end if;
                            else
                                cs_active_reg       <= '0';
                                cs_inactive_cnt_reg <= CS_INACTIVE_CLKS;
                                state_reg           <= CS_INACTIVE;
                            end if;
                        end if;

                    when CS_INACTIVE =>
                        if cs_inactive_cnt_reg > 0 then
                            cs_inactive_cnt_reg <= cs_inactive_cnt_reg - 1;
                        else
                            state_reg <= IDLE;
                        end if;

                end case;

            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- RX counter
    --------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if cs_active_reg = '0' then
                rx_count_reg <= (others => '0');
            elsif rx_data_valid_int = '1' then
                rx_count_reg <= rx_count_reg + 1;
            end if;
        end if;
    end process;
    
    rx_data_valid <= rx_data_valid_int;
    rx_byte       <= rx_byte_int;
    rx_count      <= rx_count_reg;
        
    spi_cs_n <= not cs_active_reg;
    
    tx_ready <= '1' when (state_reg = IDLE) or (state_reg = TRANSFER and master_ready = '1' and tx_count_reg > 0) else '0';

end architecture;
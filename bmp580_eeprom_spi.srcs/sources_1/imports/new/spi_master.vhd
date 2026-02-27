library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SPI_Master is
    generic (
        SPI_MODE          : integer := 0;
        CLKS_PER_HALF_BIT : integer := 2
    );
    port (
        rst_l : in std_logic;
        clk   : in std_logic;
        -- TX (MOSI) Signals
        tx_byte   : in std_logic_vector(7 downto 0);   -- Byte to transmit on MOSI
        tx_data_valid     : in std_logic;              -- Data Valid Pulse with tx_byte
        tx_ready  : out std_logic;                     -- Transmit Ready for next byte
        -- RX (MISO) Signals
        rx_data_valid   : out std_logic;               -- Data Valid pulse (1 clock cycle)
        rx_byte : out std_logic_vector(7 downto 0);    -- Byte received on MISO
        -- SPI Interface
        spi_clk  : out std_logic;
        spi_miso : in  std_logic;
        spi_mosi : out std_logic
    );
end entity SPI_Master;

architecture RTL of SPI_Master is
    -- SPI Interface (All Runs at SPI Clock Domain)
    signal cpol : std_logic;     -- Clock polarity
    signal cpha : std_logic;     -- Clock phase
    
    signal spi_clk_count_reg : integer range 0 to CLKS_PER_HALF_BIT*2-1;
    signal spi_clk_reg       : std_logic;
    signal spi_clk_edges_reg : integer range 0 to 16;
    signal leading_edge_reg  : std_logic;
    signal trailing_edge_reg : std_logic;
    signal tx_data_valid_reg : std_logic;
    signal tx_byte_reg       : std_logic_vector(7 downto 0);
    
    signal rx_bit_count_reg : unsigned(2 downto 0);
    signal tx_bit_count_reg : unsigned(2 downto 0);
    signal rx_ready_reg     : std_logic;
begin

    -- CPOL: Clock Polarity
    cpol <= '1' when (SPI_MODE = 2) or (SPI_MODE = 3) else '0';

    -- CPHA: Clock Phase
    cpha <= '1' when (SPI_MODE = 1) or (SPI_MODE = 3) else '0';

    -- Purpose: Generate SPI Clock correct number of times when DV pulse comes
    Edge_Indicator : process (clk)
    begin
        if rising_edge(clk) then
        
            if rst_l = '0' then
                rx_ready_reg      <= '0';
                spi_clk_edges_reg <= 0;
                leading_edge_reg  <= '0';
                trailing_edge_reg <= '0';
                spi_clk_reg       <= cpol; -- assign default state to idle state
                spi_clk_count_reg <= 0;
                
            else 
                -- Default assignments
                leading_edge_reg  <= '0';
                trailing_edge_reg <= '0';
                
                if tx_data_valid = '1' then
                    rx_ready_reg <= '0';
                    spi_clk_edges_reg <= 16;  -- Total # edges in one byte ALWAYS 16
                    
                elsif spi_clk_edges_reg > 0 then
                    rx_ready_reg <= '0';
                    
                    if spi_clk_count_reg = CLKS_PER_HALF_BIT*2-1 then
                        spi_clk_edges_reg <= spi_clk_edges_reg - 1;
                        trailing_edge_reg <= '1';
                        spi_clk_count_reg <= 0;
                        spi_clk_reg       <= not spi_clk_reg;
                        
                    elsif spi_clk_count_reg = CLKS_PER_HALF_BIT-1 then
                        spi_clk_edges_reg <= spi_clk_edges_reg - 1;
                        leading_edge_reg  <= '1';
                        spi_clk_count_reg <= spi_clk_count_reg + 1;
                        spi_clk_reg       <= not spi_clk_reg;
                        
                    else
                        spi_clk_count_reg <= spi_clk_count_reg + 1;
                    end if;
                    
                else
                    rx_ready_reg <= '1';
                end if;
            end if;
        end if;
    end process Edge_Indicator;
    
         
    -- Purpose: Register tx_byte when Data Valid is pulsed.
    -- Keeps local storage of byte in case higher level module changes the data
    Byte_Reg : process (clk)
    begin
        if rising_edge(clk) then
        
            if rst_l = '0' then
                tx_byte_reg       <= X"00";
                tx_data_valid_reg <= '0';
            else
                tx_data_valid_reg <= tx_data_valid; -- 1 clock cycle delay
                
                if tx_data_valid = '1' then
                    tx_byte_reg <= tx_byte;
                end if;
            end if;
        end if;
    end process Byte_Reg;
    
    
    -- Purpose: Generate MOSI data
    -- Works with both CPHA=0 and CPHA=1
    MOSI_Data : process (clk)
    begin
        if rising_edge(clk) then
        
            if rst_l = '0' then
                spi_mosi         <= '0';
                tx_bit_count_reg <= "111";          -- Send MSB first
                
            else
                -- If ready is high, reset bit counts to default
                if rx_ready_reg = '1' then
                    tx_bit_count_reg <= "111";
                    
                -- Catch the case where we start transaction and CPHA = 0
                elsif (tx_data_valid_reg = '1' and cpha = '0') then
                    spi_mosi         <= tx_byte_reg(7);
                    tx_bit_count_reg <= "110";        -- 6
                    
                elsif (leading_edge_reg = '1' and cpha = '1') or (trailing_edge_reg = '1' and cpha = '0') then
                    tx_bit_count_reg <= tx_bit_count_reg - 1;
                    spi_mosi         <= tx_byte_reg(to_integer(tx_bit_count_reg));
                end if;
            end if;
        end if;
    end process MOSI_Data;
    
    
    -- Purpose: Read in MISO data.
    MISO_Data : process (clk)
    begin
        if rising_edge(clk) then
        
            if rst_l = '0' then
                rx_byte          <= X"00";
                rx_data_valid    <= '0';
                rx_bit_count_reg <= "111";          -- Starts at 7
                
            else
                -- Default Assignments
                rx_data_valid <= '0';
                
                if rx_ready_reg = '1' then -- Check if ready, if so reset count to default
                    rx_bit_count_reg <= "111";        -- Starts at 7
                    
                elsif (leading_edge_reg = '1' and cpha = '0') or (trailing_edge_reg = '1' and cpha = '1') then
                    rx_byte(to_integer(rx_bit_count_reg)) <= spi_miso;  -- Sample data
                    rx_bit_count_reg                      <= rx_bit_count_reg - 1;
                    
                    if rx_bit_count_reg = "000" then
                        rx_data_valid <= '1';   -- Byte done, pulse Data Valid
                    end if;
                end if;
            end if;
        end if;
    end process MISO_Data;
    
    
    -- Purpose: Add clock delay to signals for alignment.
    SPI_Clock : process (clk)
    begin
        if rising_edge(clk) then
        
            if rst_l = '0' then
                spi_clk  <= cpol;
                
            else
                spi_clk <= spi_clk_reg;
            end if;
        end if;
    end process SPI_Clock;
    
    tx_ready <= rx_ready_reg;
end architecture RTL;
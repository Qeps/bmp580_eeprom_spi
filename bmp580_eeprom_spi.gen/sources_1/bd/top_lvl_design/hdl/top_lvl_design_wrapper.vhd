--Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
--Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
----------------------------------------------------------------------------------
--Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
--Date        : Sat Feb 28 21:17:21 2026
--Host        : DESKTOP-L7RS5J6 running 64-bit major release  (build 9200)
--Command     : generate_target top_lvl_design_wrapper.bd
--Design      : top_lvl_design_wrapper
--Purpose     : IP block netlist
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity top_lvl_design_wrapper is
  port (
    CLK100MHZ : in STD_LOGIC;
    LD2 : out STD_LOGIC;
    LD3 : out STD_LOGIC;
    SW3 : in STD_LOGIC;
    my_CS1 : out STD_LOGIC;
    my_MISO : in STD_LOGIC;
    my_MOSI : out STD_LOGIC;
    my_SCK : out STD_LOGIC
  );
end top_lvl_design_wrapper;

architecture STRUCTURE of top_lvl_design_wrapper is
  component top_lvl_design is
  port (
    SW3 : in STD_LOGIC;
    CLK100MHZ : in STD_LOGIC;
    LD2 : out STD_LOGIC;
    my_MISO : in STD_LOGIC;
    my_MOSI : out STD_LOGIC;
    my_SCK : out STD_LOGIC;
    LD3 : out STD_LOGIC;
    my_CS1 : out STD_LOGIC
  );
  end component top_lvl_design;
begin
top_lvl_design_i: component top_lvl_design
     port map (
      CLK100MHZ => CLK100MHZ,
      LD2 => LD2,
      LD3 => LD3,
      SW3 => SW3,
      my_CS1 => my_CS1,
      my_MISO => my_MISO,
      my_MOSI => my_MOSI,
      my_SCK => my_SCK
    );
end STRUCTURE;

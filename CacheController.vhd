library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity CacheController is
    Port ( clk 	      : in  STD_LOGIC;
			ADDR 	  : out  STD_LOGIC_VECTOR(15 downto 0);
			DOUT 	  : out  STD_LOGIC_VECTOR(7 downto 0);
			sAddra    : out  STD_LOGIC_VECTOR(7 downto 0);
			sDina     : out  STD_LOGIC_VECTOR(7 downto 0);
			sDouta    : out  STD_LOGIC_VECTOR(7 downto 0);
			sD_Addra  : out  STD_LOGIC_VECTOR(15 downto 0);
			sD_Dina   : out  STD_LOGIC_VECTOR(7 downto 0);
			sD_Douta  : out  STD_LOGIC_VECTOR(7 downto 0);
			cacheAddr : out  STD_LOGIC_VECTOR(7 downto 0);
            WR_RD, MEMSTRB, RDY ,CS	: out  STD_LOGIC);
end CacheController;

architecture Behavioral of CacheController is
--CPU Signals
	signal CPU_Dout, CPU_Din	: STD_LOGIC_VECTOR(7 downto 0);
	signal CPU_ADD 				: STD_LOGIC_VECTOR (15 downto 0);
	signal CPU_W_R,CPU_CS 		: STD_LOGIC;
	signal CPU_RDY					: STD_LOGIC;
	signal cpu_tag				   : STD_LOGIC_VECTOR(7 downto 0);
	signal index				   : STD_LOGIC_VECTOR(2 downto 0);
	signal offset		         : STD_LOGIC_VECTOR(4 downto 0);
	signal Tag_index				: STD_LOGIC_VECTOR(10 downto 0);
	
--SRAM(cache memory) Signals
	signal Dbit				: STD_LOGIC_VECTOR(7 downto 0):= "00000000";
	signal Vbit				: STD_LOGIC_VECTOR(7 downto 0):= "00000000";
	signal sADD, sDin, sDout 		: STD_LOGIC_VECTOR(7 downto 0);
	signal sWen				: STD_LOGIC_VECTOR(0 DOWNTO 0);
	signal TAGWen				: STD_LOGIC := '0';
	
--SDRAM Signals
	signal SDRAM_Din,SDRAM_Dout	: STD_LOGIC_VECTOR(7 downto 0);
	signal SDRAM_ADD					: STD_LOGIC_VECTOR(15 downto 0);
	signal SDRAM_MSTRB,SDRAM_W_R	: STD_LOGIC;
	signal counter						: integer := 0;
	signal sdoffset					: integer := 0;

--SRAM array
type cachememory is array (7 downto 0) of STD_LOGIC_VECTOR(7 downto 0);
	signal memtag: cachememory := ((others=> (others=>'0')));

--ICON & VIO  & ILA Signals 
	signal control0 : STD_LOGIC_VECTOR(35 downto 0);
	signal ila_data : std_logic_vector(99 downto 0);
	signal trig0 	: std_logic_vector(0 TO 0);

--State Signals
	signal state 	: STD_LOGIC_VECTOR(3 downto 0) := "0000";
	
--Components
	COMPONENT SDRAMController 
    Port ( 
		clk		: in  STD_LOGIC;
		ADDR 		: in  STD_LOGIC_VECTOR (15 downto 0);
      WR_RD 	: in  STD_LOGIC;
      MEMSTRB 	: in  STD_LOGIC;
      DIN 		: in  STD_LOGIC_VECTOR (7 downto 0);
      DOUT 		: out STD_LOGIC_VECTOR (7 downto 0));
	END COMPONENT;
	
	COMPONENT SRAM
	PORT (
    clka 		: IN STD_LOGIC;
    wea 			: IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra 		: IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    dina 		: IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    douta 		: OUT STD_LOGIC_VECTOR(7 DOWNTO 0));
	END COMPONENT;
	
	COMPONENT CPU_gen 
	Port ( 
		clk 		: in  STD_LOGIC;
      rst 		: in  STD_LOGIC;
      trig 		: in  STD_LOGIC;
      Address 	: out STD_LOGIC_VECTOR (15 downto 0);
      wr_rd 	: out STD_LOGIC;
      cs 		: out STD_LOGIC;
      Dout 		: out STD_LOGIC_VECTOR (7 downto 0));
	END COMPONENT;	
	
	COMPONENT icon
	PORT (
    CONTROL0 	: INOUT STD_LOGIC_VECTOR(35 DOWNTO 0));
	END COMPONENT;
	
	COMPONENT ila
	PORT (
    CONTROL 	: INOUT STD_LOGIC_VECTOR(35 DOWNTO 0);
    CLK 			: IN STD_LOGIC;
    DATA 		: IN STD_LOGIC_VECTOR(99 DOWNTO 0);
    TRIG0 		: IN STD_LOGIC_VECTOR(0 downto 0));
	END COMPONENT;
BEGIN
--PORT MAPS
	myCPU_gen 	: CPU_gen			Port Map (clk,'0',CPU_RDY,CPU_ADD,CPU_W_R,CPU_CS,CPU_Dout);
	SDRAM 		: SDRAMController	Port Map (clk,SDRAM_ADD,SDRAM_W_R,SDRAM_MSTRB,SDRAM_Din,SDRAM_Dout);
	mySRAM 		: SRAM				Port Map (clk,sWen,sADD, sDin, sDout);
	myIcon 		: icon 				Port Map (CONTROL0);
	myILA 		: ila					Port Map (CONTROL0,CLK,ila_data, TRIG0);
	
process(clk, CPU_CS)		
	begin
		if (clk'event AND clk = '1') then
		if(state = "0001") then --Hit/Miss Detection
			CPU_RDY <= '0';
		  if(Vbit(to_integer(unsigned(index))) = '1' AND memtag(to_integer(unsigned(index))) = cpu_tag) then
		    if(CPU_W_R = '1') then --hit
		      state <= "0010";--hit write
		    else
		      state <= "0011"; --hit read
		    end if;
			else--miss
				if(Dbit(to_integer(unsigned(index))) = '1') then
					state <= "0100"; --miss d =1 
				else
					state <= "0101"; -- miss d = 0
			 end if;
		  end if;
		
		elsif(state = "1001") then --Setup
			CPU_RDY <= '0';
			cpu_tag <= CPU_ADD(15 downto 8);
			index <= CPU_ADD(7 downto 5);
			offset <= CPU_ADD(4 downto 0);
			SDRAM_ADD(15 downto 5) <= CPU_ADD(15 downto 5);
			sADD(7 downto 0) <= CPU_ADD(7 downto 0);
			sWen <= "0";
			state <= "0001";
		
		elsif(state = "0010") then --Hit Write
			sWen <= "1";
			Dbit(to_integer(unsigned(index))) <= '1';
			Vbit(to_integer(unsigned(index))) <= '1';
			sDin <= CPU_Dout;
			CPU_Din <= "00000000";
			state <= "0000";
		
		elsif(state = "0011") then --Hit Read
			sWen  <= "1";
			CPU_Din <= sDout;
			state <= "0000";
		
		elsif(state = "0100") then --Miss D = 1 Cache-> SDRAM
			if (counter = 64) then
					counter <= 0;
					Dbit(to_integer(unsigned(index))) <= '0';
					sdoffset <= 0;
					state <= "0101";
				else
					if (counter mod 2 = 1) then
						SDRAM_MSTRB <= '0';
					else
						SDRAM_ADD(4 downto 0) <= STD_LOGIC_VECTOR(to_unsigned(sdoffset, offset'length));
						SDRAM_W_R <= '1';
						sADD(7 downto 5) <= index;
						sADD(4 downto 0) <= STD_LOGIC_VECTOR(to_unsigned(sdoffset, offset'length));
						sWen <= "0";
						SDRAM_Din <= sDout;
						SDRAM_MSTRB <= '1';
						sdoffset <= sdoffset + 1;
					end if;
					counter <= counter + 1;
end if;
			
			
		elsif(state = "0101") then --Miss D = 0 SDRAM -> Cache
			if (counter = 64) then
					counter <= 0;
					Vbit(to_integer(unsigned(index))) <= '1';
					memtag(to_integer(unsigned(index))) <= cpu_tag;
					sdoffset <= 0;
					state <= "0001";
				else
					if (counter mod 2 = 1) then
						SDRAM_MSTRB <= '0';
					else
						SDRAM_ADD(4 downto 0) <= STD_LOGIC_VECTOR(to_unsigned(sdoffset, offset'length));
						SDRAM_W_R <= '0';
						SDRAM_MSTRB <= '1';
						sADD(7 downto 5) <= index;
						sADD(4 downto 0) <= STD_LOGIC_VECTOR(to_unsigned(sdoffset, offset'length));
						sDin <= SDRAM_Dout;
						sWen <= "1";
						sdoffset <= sdoffset + 1;
					end if;
					counter <= counter + 1;
			end if;
			  
		 elsif(state = "0000") then
		 CPU_RDY <= '1';
			if(CPU_CS = '1') then
				state <= "1001";
			--else
				--state <= "0000";
			end if;
		end if;	
	end if;
end process;
	
	MEMSTRB <= SDRAM_MSTRB;
	ADDR 	<= CPU_ADD;
	WR_RD <= CPU_W_R;
	DOUT	<= CPU_Din;
	RDY	<= CPU_RDY;
	CS 	<= CPU_CS;
	
	sAddra <= sADD;
	sDina <= sDin;
	sDouta <= sDout;
	
	sD_Addra <= SDRAM_ADD;
	sD_Dina <= SDRAM_Din;
	sD_Douta <= SDRAM_Dout;
	
	cacheAddr <= CPU_ADD(15 downto 8);
	
-- MAP THE ILA PORTS
	ila_data(15 downto 0) <= CPU_ADD;
	ila_data(16) <= CPU_W_R;
	ila_data(17) <= CPU_RDY;
	ila_data(18) <= SDRAM_MSTRB;
	ila_data(26 downto 19) <= CPU_Din;
	ila_data(30 downto 27) <= state;
	ila_data(31) <= CPU_CS;
	ila_data(32) <= Vbit(to_integer(unsigned(index)));
	ila_data(33) <= Dbit(to_integer(unsigned(index)));
	ila_data(34) <= TAGWen;
	ila_data(42 downto 35) <= sADD;
	ila_data(50 downto 43) <= sDin;
	ila_data(58 downto 51) <= sDout;
	ila_data(74 downto 59) <= SDRAM_ADD;
	ila_data(82 downto 75) <= SDRAM_Din;
	ila_data(90 downto 83) <= SDRAM_Dout;
	ila_data(98 downto 91) <= memtag(to_integer(unsigned(index)));

end Behavioral;
import "forge-std/Test.sol";

import { Denominations } from "chainlink/Denominations.sol";

import { MockReceivables } from "../mock/MockReceivables.sol";
import { RevenueToken } from "../mock/RevenueToken.sol";
import { RevenueToken4626 } from "../mock/RevenueToken4626.sol";

import { LineLib } from "../utils/LineLib.sol";
import { CreditLib } from "../utils/CreditLib.sol";
import { LineFactory } from "../modules/factories/LineFactory.sol";
import { ModuleFactory } from "../modules/factories/ModuleFactory.sol";


contract LineFactoryTest is Test {
  LineFactory lineFactory;
  ModuleFactory moduleFactory;

  function setUp() public {
    moduleFactory = new ModuleFactory();
    lineFactory = new LineFactory(address(moduleFactory));
  }

  function test_deployed_lines_owns_modules() public {

  }
  
}

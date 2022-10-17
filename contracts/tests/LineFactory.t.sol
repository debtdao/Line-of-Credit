pragma solidity 0.8.9;

import "forge-std/Test.sol";

import { Denominations } from "chainlink/Denominations.sol";

import { MockReceivables } from "../mock/MockReceivables.sol";
import { RevenueToken } from "../mock/RevenueToken.sol";
import { RevenueToken4626 } from "../mock/RevenueToken4626.sol";

import { LineLib } from "../utils/LineLib.sol";
import { CreditLib } from "../utils/CreditLib.sol";
import { LineFactory } from "../modules/factories/LineFactory.sol";
import { ModuleFactory } from "../modules/factories/ModuleFactory.sol";
import {LineFactoryLib} from "../utils/LineFactoryLib.sol";
import {SecuredLine} from "../modules/credit/SecuredLine.sol";
import {Spigot} from "../modules/spigot/Spigot.sol";
import {Escrow} from "../modules/escrow/Escrow.sol";


contract LineFactoryTest is Test {
  SecuredLine line;
  Spigot spigot;
  Escrow escrow;
  LineFactory lineFactory;
  ModuleFactory moduleFactory;

  address oracle;
  address arbiter; 
  address borrower; 
  address swapTarget; 
  uint256 ttl = 90 days;
  address line_address;
  address  spigot_address;
  address escrow_address;



  function setUp() public {

    oracle = address(0xdebf);
    arbiter = address(0xf1c0);
    borrower = address(0xbA05);
    swapTarget = address(0xb0b0);
    

    moduleFactory = new ModuleFactory();
    lineFactory = new LineFactory(address(moduleFactory));
    
    line_address = lineFactory.deploySecuredLine(oracle, arbiter, borrower, ttl, payable(swapTarget));
    line = SecuredLine(payable(line_address));

    spigot_address = address(line.spigot());
    spigot = Spigot(payable(spigot_address));

    escrow_address = address(line.escrow());
    escrow = Escrow(payable(escrow_address));

  }

  function test_deployed_lines_own_modules()  public {
    assertEq(spigot.owner(), line_address);
    assertEq(escrow.line(), line_address);
  }
  
 function test_arbiter_cant_be_null() public {
    address arbiter = line.arbiter();
    assertTrue(arbiter != address(0x000));
  }


  function test_new_line_has_correct_spigot_and_escrow() public {
     assertEq(spigot.owner(), line_address);
     assertEq(escrow.line(), line_address);
     assertEq(address(line.escrow()), address(escrow));
     assertEq(address(line.spigot()), address(spigot));
  }

  function test_revenue_split_cannot_exceed_100() public {
    assertEq(line.defaultRevenueSplit() < 100, true);
  }

  function test_status_active() public {
    assertEq(uint(line.healthcheck()), uint(LineLib.STATUS.ACTIVE));

  }

  function test_config_params_new_line() public {

    assertEq(line.defaultRevenueSplit(), 90);
    assertEq(escrow.minimumCollateralRatio(), 3000);
    assertEq(line.deadline(), block.timestamp + 90 days);
  }

  function test_escrow_mincratio() public {
    
    assertEq(escrow.minimumCollateralRatio(), 3000);
  }


  function test_rollover_params_consistent() public {
      vm.startPrank(borrower);
      address new_line_address = lineFactory.rolloverSecuredLine(payable(line_address), borrower, oracle, arbiter, ttl);
      console.log(new_line_address);
      SecuredLine new_line = SecuredLine(payable(new_line_address));
      assertEq(new_line.deadline(), 90);
      assertEq(address(new_line.spigot()), address(line.spigot()));
      assertEq(address(new_line.escrow()), address(line.escrow()));
      assertEq(new_line.defaultRevenueSplit(), line.defaultRevenueSplit());

      address new_escrow_address = address(new_line.escrow());
      Escrow new_escrow = Escrow(payable(new_escrow_address));

      assertEq(new_escrow.minimumCollateralRatio(), escrow.minimumCollateralRatio());
    
  }

}

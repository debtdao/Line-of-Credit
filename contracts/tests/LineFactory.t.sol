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
    badarb = address(0x000);

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

    vm.expectRevert();
    fail_line_address = lineFactory.deploySecuredLine(oracle, badarb, borrower, ttl, payable(swapTarget));
    
    
  }

  

  // function test_new_line_has_correct_spigot_and_escrow() public {


  // }

  function test_revenue_split_cannot_exceed_100() public {
    assertEq(line.defaultRevenueSplit() < 100, true);
  }

  function test_status_active() public {
    assertEq(uint(line.healthcheck()), uint(LineLib.STATUS.ACTIVE));

  }

  // function test_config_params_new_line() public {

    
  // }

  // function test_escrow_mincratio() public {
  //   address escrow = line.escrow();
  //   escrow.minCRatio();
  // }

  // function test_type() public {


  // }

  // function test_rollover_params_consistent() public {

    
  // }

}

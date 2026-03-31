// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {EscrowFreelance} from "../../src/EscrowFreelance.sol";
import {EscrowFreelanceFactory} from "../../src/EscrowFreelanceFactory.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {FactoryEscrowHandler} from "./helpers/FactoryEscrowHandler.t.sol";

contract FactoryEscrowInvariantTest is Test {
    uint256 internal constant ESCROW_COUNT = 3;

    EscrowFreelanceFactory internal factory;
    HelperConfig internal helperConfig;
    FactoryEscrowHandler internal handler;

    EscrowFreelance[] internal escrows;
    address[] internal clients;
    address[] internal freelancers;
    address[] internal admins;

    function setUp() public {
        helperConfig = new HelperConfig();
        factory = new EscrowFreelanceFactory();

        for (uint256 i = 0; i < ESCROW_COUNT; i++) {
            address client = makeAddr(string(abi.encodePacked("client-", vm.toString(i))));
            address freelancer = makeAddr(string(abi.encodePacked("freelancer-", vm.toString(i))));
            address admin = makeAddr(string(abi.encodePacked("admin-", vm.toString(i))));

            clients.push(client);
            freelancers.push(freelancer);
            admins.push(admin);

            vm.startPrank(client);
            address escrowAddress = factory.createEscrow(
                freelancer, 7 days, helperConfig.activeNetworkConfig(), address(0), admin, 0
            );
            vm.stopPrank();
            escrows.push(EscrowFreelance(payable(escrowAddress)));
        }

        handler = new FactoryEscrowHandler(factory, escrows, clients, freelancers, admins);
        targetContract(address(handler));
    }

    function invariant_activeCountMatchesEscrowRegistry() public view {
        uint256 expectedActive = 0;
        for (uint256 i = 0; i < escrows.length; i++) {
            EscrowFreelance.EscrowState state = escrows[i].getEscrowState();
            if (
                state != EscrowFreelance.EscrowState.RELEASED && state != EscrowFreelance.EscrowState.REFUNDED
                    && state != EscrowFreelance.EscrowState.CANCELED && state != EscrowFreelance.EscrowState.DISPUTE
            ) {
                expectedActive++;
            }
        }

        assertEq(factory.getActiveEscrowCount(), expectedActive);
        assertEq(factory.getActiveEscrows().length, expectedActive);
    }

    function invariant_settledEscrowsHoldNoFunds() public view {
        for (uint256 i = 0; i < escrows.length; i++) {
            EscrowFreelance.EscrowState state = escrows[i].getEscrowState();
            if (
                state == EscrowFreelance.EscrowState.RELEASED || state == EscrowFreelance.EscrowState.REFUNDED
                    || state == EscrowFreelance.EscrowState.CANCELED
            ) {
                assertEq(address(escrows[i]).balance, 0);
                assertEq(escrows[i].getAmountToRelease(), 0);
            }
        }
    }

    function invariant_activeEscrowsKeepFactoryPointer() public view {
        address[] memory activeEscrows = factory.getActiveEscrows();
        for (uint256 i = 0; i < activeEscrows.length; i++) {
            assertEq(EscrowFreelance(payable(activeEscrows[i])).getFactoryAddress(), address(factory));
        }
    }

    function invariant_scanCursorWithinBounds() public view {
        uint256 activeCount = factory.getActiveEscrowCount();
        if (activeCount == 0) {
            assertEq(factory.getScanCursor(), 0);
        } else {
            assertLt(factory.getScanCursor(), activeCount);
        }
    }
}

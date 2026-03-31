// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {EscrowFreelance} from "../../src/EscrowFreelance.sol";
import {EscrowFreelanceFactory} from "../../src/EscrowFreelanceFactory.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {EscrowFreelanceHandler} from "./helpers/EscrowFreelanceHandler.t.sol";

contract EscrowFreelanceInvariantTest is Test {
    EscrowFreelance internal escrow;
    EscrowFreelanceFactory internal factory;
    EscrowFreelanceHandler internal handler;
    HelperConfig internal helperConfig;

    address internal client;
    address internal freelancer;
    address internal admin;

    function setUp() public {
        client = makeAddr("client");
        freelancer = makeAddr("freelancer");
        admin = makeAddr("admin");

        helperConfig = new HelperConfig();
        factory = new EscrowFreelanceFactory();

        vm.startPrank(client);
        address escrowAddress =
            factory.createEscrow(freelancer, 7 days, helperConfig.activeNetworkConfig(), address(0), admin, 0);
        vm.stopPrank();
        escrow = EscrowFreelance(payable(escrowAddress));

        handler = new EscrowFreelanceHandler(escrow, factory, client, freelancer, admin);
        targetContract(address(handler));
    }

    function invariant_modificationsNeverExceedTwo() public view {
        assertLe(escrow.getModificationsRequested(), 2);
    }

    function invariant_ethBalanceMatchesReleasableAmount() public view {
        assertEq(address(escrow).balance, escrow.getAmountToRelease());
    }

    function invariant_terminalStatesHaveNoPendingFunds() public view {
        EscrowFreelance.EscrowState state = escrow.getEscrowState();
        if (
            state == EscrowFreelance.EscrowState.RELEASED || state == EscrowFreelance.EscrowState.REFUNDED
                || state == EscrowFreelance.EscrowState.CANCELED
        ) {
            assertEq(escrow.getAmountToRelease(), 0);
            assertEq(address(escrow).balance, 0);
        }
    }

    function invariant_factoryActiveCountMatchesEscrowLifecycle() public view {
        EscrowFreelance.EscrowState state = escrow.getEscrowState();
        uint256 activeCount = factory.getActiveEscrowCount();

        if (
            state == EscrowFreelance.EscrowState.RELEASED || state == EscrowFreelance.EscrowState.REFUNDED
                || state == EscrowFreelance.EscrowState.CANCELED || state == EscrowFreelance.EscrowState.DISPUTE
        ) {
            assertEq(activeCount, 0);
        } else {
            assertEq(activeCount, 1);
        }
    }
}

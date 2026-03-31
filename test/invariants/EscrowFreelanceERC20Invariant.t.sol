// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {EscrowFreelance} from "../../src/EscrowFreelance.sol";
import {EscrowFreelanceFactory} from "../../src/EscrowFreelanceFactory.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {EscrowFreelanceERC20Handler} from "./helpers/EscrowFreelanceERC20Handler.t.sol";

contract EscrowFreelanceERC20InvariantTest is Test {
    EscrowFreelance internal escrow;
    EscrowFreelanceFactory internal factory;
    EscrowFreelanceERC20Handler internal handler;
    HelperConfig internal helperConfig;
    MockERC20 internal token;

    address internal client;
    address internal freelancer;
    address internal admin;

    function setUp() public {
        client = makeAddr("client");
        freelancer = makeAddr("freelancer");
        admin = makeAddr("admin");

        helperConfig = new HelperConfig();
        factory = new EscrowFreelanceFactory();
        token = new MockERC20("Test Token", "TST", 18);

        vm.startPrank(client);
        address escrowAddress =
            factory.createEscrow(freelancer, 7 days, helperConfig.activeNetworkConfig(), address(token), admin, 0);
        vm.stopPrank();
        escrow = EscrowFreelance(payable(escrowAddress));

        handler = new EscrowFreelanceERC20Handler(escrow, factory, token, client, freelancer, admin);
        targetContract(address(handler));
    }

    function invariant_tokenBalanceMatchesReleasableAmount() public view {
        assertEq(token.balanceOf(address(escrow)), escrow.getAmountToRelease());
    }

    function invariant_modificationsNeverExceedTwo() public view {
        assertLe(escrow.getModificationsRequested(), 2);
    }

    function invariant_settledStatesHaveNoEscrowedTokens() public view {
        EscrowFreelance.EscrowState state = escrow.getEscrowState();
        if (
            state == EscrowFreelance.EscrowState.RELEASED || state == EscrowFreelance.EscrowState.REFUNDED
                || state == EscrowFreelance.EscrowState.CANCELED
        ) {
            assertEq(escrow.getAmountToRelease(), 0);
            assertEq(token.balanceOf(address(escrow)), 0);
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

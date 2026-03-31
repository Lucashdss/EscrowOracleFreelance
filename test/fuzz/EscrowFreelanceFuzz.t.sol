// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {EscrowFreelance} from "../../src/EscrowFreelance.sol";
import {EscrowFreelanceFactory} from "../../src/EscrowFreelanceFactory.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract EscrowFreelanceFuzzTest is Test {
    EscrowFreelance internal escrow;
    EscrowFreelanceFactory internal factory;
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
    }

    function testFuzz_FundIncreasesAmountToRelease(uint96 amount) public {
        amount = uint96(bound(amount, 1, 100 ether));

        vm.deal(client, amount);
        vm.startPrank(client);
        escrow.fund{value: amount}(amount);
        vm.stopPrank();

        assertEq(escrow.getAmountToRelease(), amount);
        assertEq(address(escrow).balance, amount);
        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.FUNDED));
    }

    function testFuzz_RequestModificationUpdatesDeadline(uint96 amount, uint32 extensionOne, uint32 extensionTwo)
        public
    {
        amount = uint96(bound(amount, 1, 100 ether));
        extensionOne = uint32(bound(extensionOne, 1, 30 days));
        extensionTwo = uint32(bound(extensionTwo, 1, 30 days));

        vm.deal(client, amount);
        vm.startPrank(client);
        escrow.fund{value: amount}(amount);
        vm.stopPrank();

        vm.prank(freelancer);
        escrow.markWorkSubmitted();

        uint256 initialDeadline = escrow.getDeadline();

        vm.startPrank(client);
        escrow.requestModificationAndUpdateDeadline(extensionOne);
        assertEq(escrow.getDeadline(), initialDeadline + extensionOne);
        assertEq(escrow.getModificationsRequested(), 1);

        escrow.requestModificationAndUpdateDeadline(extensionTwo);
        vm.stopPrank();
        assertEq(escrow.getDeadline(), initialDeadline + extensionOne + extensionTwo);
        assertEq(escrow.getModificationsRequested(), 2);
        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.PENDING_MODIFICATION));
    }

    function testFuzz_UpfrontPaymentPaysOnlyOnce(uint96 firstAmount, uint96 secondAmount, uint16 bps) public {
        firstAmount = uint96(bound(firstAmount, 1, 100 ether));
        secondAmount = uint96(bound(secondAmount, 1, 100 ether));
        bps = uint16(bound(bps, 1, 10_000));

        vm.startPrank(client);
        address escrowAddress =
            factory.createEscrow(freelancer, 7 days, helperConfig.activeNetworkConfig(), address(0), admin, bps);
        vm.stopPrank();
        EscrowFreelance escrowWithBps = EscrowFreelance(payable(escrowAddress));

        vm.deal(client, uint256(firstAmount) + uint256(secondAmount));

        uint256 expectedUpfront = (uint256(firstAmount) * bps) / 10_000;
        uint256 freelancerBalanceBefore = freelancer.balance;

        vm.startPrank(client);
        escrowWithBps.fund{value: firstAmount}(firstAmount);
        escrowWithBps.fund{value: secondAmount}(secondAmount);
        vm.stopPrank();

        assertEq(freelancer.balance - freelancerBalanceBefore, expectedUpfront);
        assertEq(escrowWithBps.getAmountToRelease(), uint256(firstAmount) - expectedUpfront + uint256(secondAmount));
        assertEq(address(escrowWithBps).balance, escrowWithBps.getAmountToRelease());
    }
}

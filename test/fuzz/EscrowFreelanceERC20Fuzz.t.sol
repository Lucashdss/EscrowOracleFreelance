// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {EscrowFreelance} from "../../src/EscrowFreelance.sol";
import {EscrowFreelanceFactory} from "../../src/EscrowFreelanceFactory.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract EscrowFreelanceERC20FuzzTest is Test {
    EscrowFreelance internal escrow;
    EscrowFreelanceFactory internal factory;
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
        address escrowAddress = factory.createEscrow(
            freelancer, 7 days, helperConfig.activeNetworkConfig(), address(token), admin, 0
        );
        vm.stopPrank();
        escrow = EscrowFreelance(payable(escrowAddress));
    }

    function testFuzz_ERC20FundingIncreasesAmount(uint96 amount) public {
        amount = uint96(bound(amount, 1, 1_000_000e18));

        token.mint(client, amount);

        vm.startPrank(client);
        token.approve(address(escrow), amount);
        escrow.fund(amount);
        vm.stopPrank();

        assertEq(escrow.getAmountToRelease(), amount);
        assertEq(token.balanceOf(address(escrow)), amount);
        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.FUNDED));
    }

    function testFuzz_ERC20ConfirmDeliveryReleasesExpectedFunds(uint96 amount) public {
        amount = uint96(bound(amount, 1, 1_000_000e18));

        token.mint(client, amount);

        vm.startPrank(client);
        token.approve(address(escrow), amount);
        escrow.fund(amount);
        vm.stopPrank();

        vm.prank(freelancer);
        escrow.markWorkSubmitted();

        uint256 expectedFee = uint256(amount) / 100;
        uint256 expectedRelease = uint256(amount) - expectedFee;
        uint256 freelancerBalanceBefore = token.balanceOf(freelancer);
        uint256 adminBalanceBefore = token.balanceOf(admin);

        vm.prank(client);
        escrow.confirmDelivery();

        assertEq(token.balanceOf(freelancer) - freelancerBalanceBefore, expectedRelease);
        assertEq(token.balanceOf(admin) - adminBalanceBefore, expectedFee);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.getAmountToRelease(), 0);
        assertEq(factory.getActiveEscrowCount(), 0);
    }

    function testFuzz_ERC20RefundAfterDeadlineReturnsExpectedFunds(uint96 amount, uint32 extraTime) public {
        amount = uint96(bound(amount, 1, 1_000_000e18));
        extraTime = uint32(bound(extraTime, 1, 30 days));

        token.mint(client, amount);

        vm.startPrank(client);
        token.approve(address(escrow), amount);
        escrow.fund(amount);
        vm.stopPrank();

        vm.warp(escrow.getDeadline() + extraTime);

        uint256 expectedFee = uint256(amount) / 100;
        uint256 expectedRefund = uint256(amount) - expectedFee;
        uint256 clientBalanceBefore = token.balanceOf(client);
        uint256 adminBalanceBefore = token.balanceOf(admin);

        factory.processExpiredEscrows();

        assertEq(token.balanceOf(client) - clientBalanceBefore, expectedRefund);
        assertEq(token.balanceOf(admin) - adminBalanceBefore, expectedFee);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.getAmountToRelease(), 0);
        assertEq(uint256(escrow.getEscrowState()), uint256(EscrowFreelance.EscrowState.REFUNDED));
        assertEq(factory.getActiveEscrowCount(), 0);
    }
}

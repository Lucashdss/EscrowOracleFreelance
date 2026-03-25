// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
* @title EscrowFreelance
* @author Lucas Santos
* @notice A decentralized escrow contract for freelance work, allowing clients to securely fund projects and freelancers
 to receive payments upon delivery. The contract supports both ETH and ERC20 tokens, with automatic refunds if deadlines
  are missed and Chainlink Automation for upkeep.
* @dev The contract uses Chainlink Automation to automatically refund clients if the freelancer misses the delivery deadline
 and to release funds to the freelancer once delivery is confirmed by the client. It also integrates with a Chainlink Price Feed
 to set minimum payment amounts in USD, ensuring fair compensation for freelancers regardless of market fluctuations.
*/

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Errors} from "./libraries/Errors.sol";
import {IEscrowFreelanceFactory} from "./interfaces/IEscrowFreelanceFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract EscrowFreelance {
    using Errors for *;
    using SafeERC20 for IERC20;

    enum EscrowState {
        CREATED,
        FUNDED,
        WORK_SUBMITTED,
        PENDING_MODIFICATION,
        RELEASED,
        REFUNDED,
        CANCELED,
        DISPUTE
    }

    // variables are stored here
    EscrowState private state;
    bool private deliveryConfirmed;
    bool private upFrontPaymentMade;
    uint256 private amountToRelease;
    uint256 private minimumPriceUSDinEther;
    uint256 private modificationsRequested;
    uint256 private immutable iBPS; // basis points to calculate upfront payment
    uint256 private deadline;
    address public immutable iToken; // address(0) = ETH, otherwise ERC20
    address private immutable iClient;
    address private immutable iFreelancer;
    address internal immutable iDataFeed;
    address private immutable iAdmin;
    address private immutable iFactory;

    event StateChanged(EscrowState newState);
    event FundsReleased(address freelancer, uint256 amount);
    event FundsRefunded(address client, uint256 amount);
    event DeliveryConfirmed(address client);
    event MinimumPriceUpdated(uint256 newMinimumPrice);
    event UpfrontPaymentSent(uint256 bps, uint256 amountSent);
    event ContractFunded(address indexed client, uint256 amount, address indexed token, bool isETH);
    event FeeCharged(address indexed admin, uint256 feeAmount, address indexed token, bool isETH);
    event DisputeInitiated(address initiator);
    event ConflictResolved(address resolver, address winner);

    modifier OnlyClient() {
        if (msg.sender != iClient) {
            revert Errors.OnlyClient();
        }
        _;
    }

    modifier OnlyFreelancer() {
        if (msg.sender != iFreelancer) {
            revert Errors.OnlyFreelancer();
        }
        _;
    }

    modifier OnlyAdmin() {
        if (msg.sender != iAdmin) {
            revert Errors.OnlyAdmin();
        }
        _;
    }

    modifier OnlyClientOrFreelancer() {
        if (msg.sender != iClient && msg.sender != iFreelancer) {
            revert Errors.OnlyClientOrFreelancer();
        }
        _;
    }

    modifier OnlyFactory() {
        if (msg.sender != iFactory) {
            revert Errors.NotPerformUpkeep();
        }
        _;
    }

    modifier beforeFund(uint256 amount) {
        if (state == EscrowState.RELEASED || state == EscrowState.REFUNDED) {
            revert Errors.ContractHasBeenAlreadyReleasedOrRefunded();
        }
        if (state == EscrowState.CANCELED) {
            revert Errors.ContractCanceled();
        }
        if (state == EscrowState.DISPUTE) {
            revert Errors.ContractInDispute();
        }

        if (minimumPriceUSDinEther != 0 && amount < minimumPriceUSDinEther) {
            revert Errors.AmountIsInferiorToMinimumUSD();
        }

        if (iToken != address(0)) {
            uint256 allowance = IERC20(iToken).allowance(msg.sender, address(this));
            if (allowance < amount) {
                revert Errors.InsufficientAllowance();
            }
            uint256 balance = IERC20(iToken).balanceOf(msg.sender);
            if (balance < amount) {
                revert Errors.InsufficientTokenBalance();
            }
        }

        _;
    }

    constructor(
        address _client,
        address _freelancer,
        uint256 _deliveryPeriod,
        address _dataFeed,
        address _token,
        address _factory,
        address _admin,
        uint256 _bps
    ) {
        iClient = _client;
        iFreelancer = _freelancer;
        iDataFeed = _dataFeed;
        iToken = _token; // address(0) = ETH
        iFactory = _factory;
        iAdmin = _admin;

        if (_bps > 10000) {
            revert Errors.InvalidBps();
        }
        iBPS = _bps;

        unchecked {
            deadline = block.timestamp + _deliveryPeriod;
        }
        state = EscrowState.CREATED;

        if (_bps > 0) {
            upFrontPaymentMade = false;
        } else {
            upFrontPaymentMade = true;
        }

        emit StateChanged(EscrowState.CREATED);
    }

    function setMinimumPriceUSD(uint256 usdAmount) external OnlyFreelancer {
        if (state != EscrowState.CREATED) {
            revert Errors.ContractHasBeenAlreadyFunded();
        }
        uint256 ethAmount = convertAmountFromUSDtoETH(usdAmount);
        minimumPriceUSDinEther = ethAmount;

        emit MinimumPriceUpdated(usdAmount);
    }

    function convertAmountFromUSDtoETH(uint256 usdAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(iDataFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 adjustedPrice = uint256(price) * 1e10; // Adjust to 18 decimals

        // ceil instead of floor to avoid rounding below minimum
        uint256 ethAmount = (usdAmount * 1e18 + adjustedPrice - 1) / adjustedPrice;
        return ethAmount;
    }

    function upfrontPayment() internal {
        if (upFrontPaymentMade) {
            return;
        }

        uint256 upfrontAmount = (amountToRelease * iBPS) / 10000;
        amountToRelease -= upfrontAmount;
        upFrontPaymentMade = true;
        _transferAmount(iFreelancer, upfrontAmount);
        emit UpfrontPaymentSent(iBPS, upfrontAmount);
    }

    function fund(uint256 amount) external payable OnlyClient beforeFund(amount) {
        bool shouldSetFundedState = state == EscrowState.CREATED;
        if (shouldSetFundedState) {
            state = EscrowState.FUNDED;
        }

        if (iToken == address(0)) {
            // ETH escrow
            if (msg.value != amount) {
                revert Errors.TokenAddressIsNotERC20();
            }
        } else {
            // ERC20 escrow
            if (msg.value != 0) {
                revert Errors.TokenAddressIsNotETH();
            }

            IERC20(iToken).safeTransferFrom(msg.sender, address(this), amount);
        }

        amountToRelease += amount;

        if (iBPS > 0 && !upFrontPaymentMade) {
            upfrontPayment();
        }

        if (shouldSetFundedState) {
            emit StateChanged(EscrowState.FUNDED);
        }
        emit ContractFunded(msg.sender, amount, iToken, iToken == address(0));
    }

    function markWorkSubmitted() external OnlyFreelancer {
        if (state != EscrowState.FUNDED && state != EscrowState.PENDING_MODIFICATION) {
            revert Errors.InvalidState();
        }

        state = EscrowState.WORK_SUBMITTED;
        emit StateChanged(EscrowState.WORK_SUBMITTED);
    }

    function confirmDelivery() external OnlyClient {
        if (state != EscrowState.WORK_SUBMITTED) {
            revert Errors.InvalidState();
        }

        deliveryConfirmed = true;
        emit DeliveryConfirmed(msg.sender);
        releaseFunds();
    }

    function requestModificationAndUpdateDeadline(uint256 deadlineExtension) external OnlyClient {
        if (state != EscrowState.WORK_SUBMITTED && state != EscrowState.PENDING_MODIFICATION) {
            revert Errors.InvalidState();
        }
        if (modificationsRequested >= 2) {
            revert Errors.MaxModificationsReached();
        }

        modificationsRequested += 1;

        unchecked {
            deadline += deadlineExtension;
        }

        state = EscrowState.PENDING_MODIFICATION;
        emit StateChanged(EscrowState.PENDING_MODIFICATION);
    }

    function cancelEscrow() external OnlyClient {
        if (state != EscrowState.CREATED) {
            revert Errors.InvalidState();
        }

        state = EscrowState.CANCELED;
        emit StateChanged(EscrowState.CANCELED);
        _deactivateInFactory();
    }

    function initiateDispute() external OnlyClientOrFreelancer {
        if (state != EscrowState.WORK_SUBMITTED && state != EscrowState.PENDING_MODIFICATION) {
            revert Errors.InvalidState();
        }

        state = EscrowState.DISPUTE;
        emit StateChanged(EscrowState.DISPUTE);
        emit DisputeInitiated(msg.sender);
        _deactivateInFactory();
    }

    function resolveConflict(address winner) external OnlyAdmin {
        if (state != EscrowState.DISPUTE) {
            revert Errors.InvalidState();
        }
        if (winner != iClient && winner != iFreelancer) {
            revert Errors.InvalidConflictWinner();
        }

        if (winner == iClient) {
            deadlinePassedRefundClient();
        } else {
            releaseFunds();
        }

        emit ConflictResolved(msg.sender, winner);
    }

    function chargeFees() internal {
        uint256 feeAmount = amountToRelease / 100;

        if (feeAmount == 0) {
            emit FeeCharged(iAdmin, feeAmount, iToken, iToken == address(0));
            return;
        }

        amountToRelease -= feeAmount;
        _transferAmount(iAdmin, feeAmount);
        emit FeeCharged(iAdmin, feeAmount, iToken, iToken == address(0));
    }

    function releaseFunds() internal {
        if (state != EscrowState.WORK_SUBMITTED && state != EscrowState.DISPUTE) {
            revert Errors.InvalidState();
        }
        if (state == EscrowState.WORK_SUBMITTED && !deliveryConfirmed) {
            revert Errors.DeliverNotConfirmed();
        }

        state = EscrowState.RELEASED;
        emit StateChanged(EscrowState.RELEASED);
        chargeFees();

        uint256 releaseAmount = amountToRelease;
        amountToRelease = 0;
        _transferAmount(iFreelancer, releaseAmount);
        emit FundsReleased(iFreelancer, releaseAmount);
        _deactivateInFactory();
    }

    function deadlinePassedRefundClient() internal {
        state = EscrowState.REFUNDED;
        emit StateChanged(EscrowState.REFUNDED);
        chargeFees();

        uint256 amount = amountToRelease;
        amountToRelease = 0;
        _transferAmount(iClient, amount);
        emit FundsRefunded(iClient, amount);
        _deactivateInFactory();
    }

    function _transferAmount(address receiver, uint256 amount) internal {
        if (iToken == address(0)) {
            if (address(this).balance < amount) {
                revert Errors.InsufficientFunds();
            }

            (bool success,) = payable(receiver).call{value: amount}("");
            if (!success) {
                revert Errors.TransferFailed();
            }
            return;
        }

        IERC20 token = IERC20(iToken);
        uint256 balance = token.balanceOf(address(this));
        if (balance < amount) {
            revert Errors.InsufficientFunds();
        }

        token.safeTransfer(receiver, amount);
    }

    function canAutoProcess() external view returns (bool) {
        return block.timestamp > deadline && (state == EscrowState.FUNDED || state == EscrowState.PENDING_MODIFICATION);
    }

    function autoProcess() external OnlyFactory {
        if (block.timestamp <= deadline) {
            revert Errors.DeliveryPeriodNotOver();
        }
        if (state != EscrowState.FUNDED && state != EscrowState.PENDING_MODIFICATION) {
            revert Errors.InvalidState();
        }
        deadlinePassedRefundClient();
    }

    function _deactivateInFactory() internal {
        IEscrowFreelanceFactory(iFactory).deactivateEscrow(address(this));
    }

    function getDeadline() external view returns (uint256) {
        return deadline;
    }

    function getAmountToRelease() external view returns (uint256) {
        return amountToRelease;
    }

    function getClientAddress() external view returns (address) {
        return iClient;
    }

    function getFreelancerAddress() external view returns (address) {
        return iFreelancer;
    }

    function getEscrowState() external view returns (EscrowState) {
        return state;
    }

    function getDeliveryConfirmedState() external view returns (bool) {
        return deliveryConfirmed;
    }

    function getDataFeedAddress() external view returns (address) {
        return iDataFeed;
    }

    function getMinimumPriceUSD() external view returns (uint256) {
        return minimumPriceUSDinEther;
    }

    function getModificationsRequested() external view returns (uint256) {
        return modificationsRequested;
    }

    function getTokenAddress() external view returns (address) {
        return iToken;
    }

    function getAdminAddress() external view returns (address) {
        return iAdmin;
    }

    function getFactoryAddress() external view returns (address) {
        return iFactory;
    }

    function getVersion() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(iDataFeed);
        return priceFeed.version();
    }

    fallback() external payable {
        revert("Please use the website to interact with this contract");
    }

    receive() external payable {
        revert("Please use the website to interact with this contract");
    }
}

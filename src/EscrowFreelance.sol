//SPDX-license-Identifier: MIT
pragma solidity ^0.8.19;

import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Errors} from "./libraries/Errors.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract EscrowFreelance is AutomationCompatibleInterface {
    using Errors for *;
    using SafeERC20 for IERC20;

    enum EscrowState {
        CREATED,
        FUNDED,
        DELIVERED,
        RELEASED,
        REFUNDED
    }

    // variables are stored here
    EscrowState private state;
    bool private deliveryConfirmed;
    bool private isPerformingUpkeep;
    uint256 private amountToRelease;
    uint256 private minimumPriceUSDinEther;
    uint256 private immutable deadline;
    address public immutable iToken; // address(0) = ETH, otherwise ERC20
    address private immutable iClient;
    address private immutable iFreelancer;
    address internal immutable iDataFeed;

    constructor(
        address _freelancer,
        uint32 _deliveryPeriod,
        address _dataFeed,
        address _token
    ) {
        iClient = msg.sender;
        iFreelancer = _freelancer;
        iDataFeed = _dataFeed;
        iToken = _token; // address(0) = ETH

        unchecked {
            deadline = block.timestamp + _deliveryPeriod;
        }
        state = EscrowState.CREATED;
    }

    function markDelivered() external OnlyFreelancer {
        if (state != EscrowState.FUNDED) {
            revert Errors.InvalidState();
        }

        state = EscrowState.DELIVERED;
    }

    function confirmDelivery() external OnlyClient {
        if (state != EscrowState.DELIVERED) {
            revert Errors.InvalidState();
        }

        deliveryConfirmed = true;
    }

    function releaseFunds() internal OnlyPerformUpkeep {
        if (state != EscrowState.DELIVERED) {
            revert Errors.InvalidState();
        }
        if (!deliveryConfirmed) {
            revert Errors.DeliverNotConfirmed();
        }

        state = EscrowState.RELEASED;

        if (iToken == address(0)) {
            // ETH transfer
            (bool success, ) = payable(iFreelancer).call{
                value: amountToRelease
            }("");
            if (!success) {
                revert Errors.TransferFailed();
            }
        } else {
            // ERC20 transfer
            IERC20 token = IERC20(iToken);
            uint256 balance = token.balanceOf(address(this));

            if (balance < amountToRelease) {
                revert Errors.InsufficientFunds();
            }

            token.safeTransfer(iFreelancer, amountToRelease);
        }

        amountToRelease = 0;
    }

    function fund(
        uint256 amount
    ) external payable OnlyClient beforeFund(amount) {
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
    }

    function convertAmountFromUSDtoETH(
        uint256 usdAmount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(iDataFeed);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 adjustedPrice = uint256(price) * 1e10; // Adjust to 18 decimals

        // ceil instead of floor to avoid rounding below minimum
        uint256 ethAmount = (usdAmount * 1e18 + adjustedPrice - 1) /
            adjustedPrice;
        return ethAmount;
    }

    function setMinimumPriceUSD(uint256 usdAmount) external OnlyFreelancer {
        if (state != EscrowState.CREATED) {
            revert Errors.ContractHasBeenAlreadyFunded();
        }
        uint256 ethAmount = convertAmountFromUSDtoETH(usdAmount);
        minimumPriceUSDinEther = ethAmount;
    }

    function deadlinePassedRefundClient() internal OnlyPerformUpkeep {
        state = EscrowState.REFUNDED;
        uint256 amount = amountToRelease;

        amountToRelease = 0;

        if (iToken == address(0)) {
            // ETH transfer
            (bool success, ) = payable(iClient).call{value: amount}("");
            if (!success) {
                revert Errors.TransferFailed();
            }
        } else {
            // ERC20 transfer
            IERC20 token = IERC20(iToken);
            uint256 balance = token.balanceOf(address(this));

            if (balance < amount) {
                revert Errors.InsufficientFunds();
            }

            token.safeTransfer(iClient, amount);
        }
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

    function getVersion() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(iDataFeed);
        return priceFeed.version();
    }

    function getDataFeedAddress() external view returns (address) {
        return iDataFeed;
    }

    function getMinimumPriceUSD() external view returns (uint256) {
        return minimumPriceUSDinEther;
    }

    function getTokenAddress() external view returns (address) {
        return iToken;
    }

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

    modifier OnlyPerformUpkeep() {
        if (!isPerformingUpkeep) {
            revert Errors.NotPerformUpkeep();
        }
        _;
    }

    modifier beforeFund(uint256 amount) {
        if (state == EscrowState.RELEASED || state == EscrowState.REFUNDED) {
            revert Errors.ContractHasBeenAlreadyReleasedOrRefunded();
        }

        if (minimumPriceUSDinEther != 0) {
            if (amount < minimumPriceUSDinEther) {
                revert Errors.AmountIsInferiorToMinimumUSD();
            }
        }

        _;

        if (state == EscrowState.CREATED) {
            state = EscrowState.FUNDED;
        }
    }

    function checkUpkeep(
        bytes calldata
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        // if deadline has passed and state is FUNDED, we need to perform upkeep to refund
        if (block.timestamp > deadline && state == EscrowState.FUNDED) {
            upkeepNeeded = true;
            performData = abi.encode(uint8(1)); // No additional data needed for performUpkeep
        } else if (state == EscrowState.DELIVERED && deliveryConfirmed) {
            upkeepNeeded = true;
            performData = abi.encode(uint8(2)); // No additional data needed for performUpkeep
        } else {
            upkeepNeeded = false;
            performData = "";
        }

        return (upkeepNeeded, performData);
    }

    function performUpkeep(bytes calldata performData) external override {
        uint8 action = abi.decode(performData, (uint8));
        if (action == 1) {
            isPerformingUpkeep = true;
            deadlinePassedRefundClient();
            isPerformingUpkeep = false;
        } else if (action == 2) {
            isPerformingUpkeep = true;
            releaseFunds();
            isPerformingUpkeep = false;
        }
    }
}

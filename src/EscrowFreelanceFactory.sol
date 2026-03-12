// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {EscrowFreelance} from "./EscrowFreelance.sol";
import {IEscrowFreelance} from "./interfaces/IEscrowFreelance.sol";
import {Errors} from "./libraries/Errors.sol";

contract EscrowFreelanceFactory {
    uint256 public constant DEFAULT_MAX_COUNT = 5;

    event EscrowCreated(
        address indexed escrowAddress,
        address indexed client,
        address indexed freelancer,
        address token,
        uint256 deliveryPeriod,
        address dataFeed,
        uint256 bps
    );
    event EscrowDeactivated(address indexed escrowAddress);
    event EscrowAutoProcessFailed(address indexed escrowAddress);

    address[] private sActiveEscrows;
    mapping(address escrow => uint256 indexPlusOne) private sEscrowIndexPlusOne;
    uint256 private sScanCursor;

    function createEscrow(
        address freelancer,
        uint256 deliveryPeriod,
        address dataFeed,
        address token,
        address admin,
        uint256 bps
    ) external returns (address escrow) {
        EscrowFreelance instance = new EscrowFreelance(
            msg.sender, freelancer, deliveryPeriod, dataFeed, token, address(this), admin, bps
        );
        escrow = address(instance);
        _addActiveEscrow(escrow);
        emit EscrowCreated(escrow, msg.sender, freelancer, token, deliveryPeriod, dataFeed, bps);
    }

    function processExpiredEscrows() public {
        uint256 activeCount = sActiveEscrows.length;
        if (activeCount == 0) {
            return;
        }

        uint256 inspections = DEFAULT_MAX_COUNT;
        if (inspections > activeCount) {
            inspections = activeCount;
        }

        uint256 inspected = 0;
        while (inspected < inspections && sActiveEscrows.length > 0) {
            if (sScanCursor >= sActiveEscrows.length) {
                sScanCursor = 0;
            }

            uint256 currentLength = sActiveEscrows.length;
            uint256 currentIndex = sScanCursor;
            address escrow = sActiveEscrows[currentIndex];

            sScanCursor = currentIndex + 1;
            if (sScanCursor >= currentLength) {
                sScanCursor = 0;
            }

            try IEscrowFreelance(escrow).canAutoProcess() returns (bool shouldProcess) {
                if (shouldProcess) {
                    try IEscrowFreelance(escrow).autoProcess() {}
                    catch {
                        emit EscrowAutoProcessFailed(escrow);
                    }
                }
            } catch {
                emit EscrowAutoProcessFailed(escrow);
            }

            unchecked {
                inspected++;
            }
        }
    }

    function deactivateEscrow(address escrow) external {
        if (msg.sender != escrow) {
            revert Errors.NotPerformUpkeep();
        }
        _removeActiveEscrow(escrow);
    }

    function getActiveEscrows() external view returns (address[] memory) {
        return sActiveEscrows;
    }

    function getActiveEscrowCount() external view returns (uint256) {
        return sActiveEscrows.length;
    }

    function getScanCursor() external view returns (uint256) {
        return sScanCursor;
    }

    function _addActiveEscrow(address escrow) internal {
        sActiveEscrows.push(escrow);
        sEscrowIndexPlusOne[escrow] = sActiveEscrows.length;
    }

    function _removeActiveEscrow(address escrow) internal {
        uint256 indexPlusOne = sEscrowIndexPlusOne[escrow];
        if (indexPlusOne == 0) {
            return;
        }

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = sActiveEscrows.length - 1;
        address lastEscrow = sActiveEscrows[lastIndex];

        if (index != lastIndex) {
            sActiveEscrows[index] = lastEscrow;
            sEscrowIndexPlusOne[lastEscrow] = index + 1;
        }

        sActiveEscrows.pop();
        delete sEscrowIndexPlusOne[escrow];

        if (sActiveEscrows.length == 0) {
            sScanCursor = 0;
        } else {
            if (index < sScanCursor && sScanCursor != 0) {
                unchecked {
                    sScanCursor--;
                }
            }
            if (sScanCursor >= sActiveEscrows.length) {
                sScanCursor = 0;
            }
        }

        emit EscrowDeactivated(escrow);
    }
}

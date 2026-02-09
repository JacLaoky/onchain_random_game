// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IRandomnessProvider} from "../interfaces/IRandomnessProvider.sol";
import {IRandomnessConsumer} from "../interfaces/IRandomnessConsumer.sol";

contract RandomnessProvider is AccessControl, Pausable, IRandomnessProvider {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");
    bytes32 public constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");

    struct RequestStatus {
        bool fulfilled;
        uint256[] randomWords;
        address requester;
    }

    mapping(uint256 => RequestStatus) private s_requests;
    uint256 private s_nextRequestId = 1;

    event RandomnessRequested(uint256 indexed requestId, address indexed game);
    event RandomnessFulfilled(uint256 indexed requestId, address indexed game);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
    }

    function requestRandomness(uint32 numWords) external whenNotPaused onlyRole(GAME_ROLE) returns (uint256 requestId) {
        requestId = s_nextRequestId++;
        s_requests[requestId] = RequestStatus({
            fulfilled: false,
            randomWords: new uint256[](numWords),
            requester: msg.sender
        });
        emit RandomnessRequested(requestId, msg.sender);
    }

    function getRequestStatus(uint256 requestId)
        external
        view
        returns (bool fulfilled, uint256[] memory randomWords)
    {
        RequestStatus storage request = s_requests[requestId];
        return (request.fulfilled, request.randomWords);
    }

    function rawFulfillRandomness(uint256 requestId, uint256[] calldata randomWords)
        external
        whenNotPaused
        onlyRole(FULFILLER_ROLE)
    {
        RequestStatus storage request = s_requests[requestId];
        if (request.requester == address(0)) {
            revert("UNKNOWN_REQUEST");
        }
        request.fulfilled = true;
        request.randomWords = randomWords;
        emit RandomnessFulfilled(requestId, request.requester);

        IRandomnessConsumer(request.requester).rawFulfillRandomness(requestId, randomWords);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
}

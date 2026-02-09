## On-Chain Verifiable Random Game Platform - Contract Architecture

### Goals
- Provably fair randomness using Chainlink VRF (or compatible provider).
- Two game types: lottery (time-based draw) and dice (multiplier bets).
- Shared treasury with house edge, min/max bets, and automatic payouts.
- Anti-cheating and fairness controls (commit/reveal optional for user inputs).
- Emergency pause and robust access control.

### High-Level Modules
1) Randomness Provider
- Wraps Chainlink VRF and exposes a provider-neutral interface.
- Handles request/fulfill and retry logic.

2) Treasury
- Central bankroll that holds ETH/ERC-20 and enforces risk limits.
- Calculates house edge and payouts, and executes transfers.

3) Game Contracts
- LotteryGame: accepts entries, requests randomness, draws winners on schedule.
- DiceGame: single-shot bet with odds, request randomness, resolves payout.

4) Registry/Router (optional, but recommended)
- Keeps track of enabled games and parameters.
- Allows platform upgrades without migrating treasury.

### Contract List (Proposed)
1) RandomnessProvider (VRF wrapper)
2) Treasury
3) LotteryGame
4) DiceGame
5) GameRegistry (optional)

### Access Control
- Use OpenZeppelin AccessControl for roles:
  - DEFAULT_ADMIN_ROLE: platform owner (multisig in prod).
  - MANAGER_ROLE: adjust parameters, enable/disable games.
  - PAUSER_ROLE: emergency pause.

### Emergency Controls
- All contracts inherit Pausable.
- Treasury blocks payouts when paused.
- Games block new bets when paused; allow pending resolution if safe.

### Storage and Data Flow
1) User places bet in a game contract.
2) Game validates bet using Treasury limits.
3) Game requests randomness from RandomnessProvider.
4) VRF callback triggers fulfillment.
5) Game computes outcome and requests Treasury payout.

### Interfaces

#### IRandomnessProvider
```solidity
interface IRandomnessProvider {
    function requestRandomness(uint32 numWords) external returns (uint256 requestId);
    function getRequestStatus(uint256 requestId)
        external
        view
        returns (bool fulfilled, uint256[] memory randomWords);
}
```

#### IRandomnessConsumer
```solidity
interface IRandomnessConsumer {
    function rawFulfillRandomness(uint256 requestId, uint256[] calldata randomWords) external;
}
```

#### ITreasury
```solidity
interface ITreasury {
    function getMinBet(address token) external view returns (uint256);
    function getMaxBet(address token) external view returns (uint256);
    function getHouseEdgeBps() external view returns (uint256);
    function canPayout(address token, uint256 amount) external view returns (bool);
    function payout(address token, address to, uint256 amount) external;
    function collect(address token, address from, uint256 amount) external;
}
```

#### IGame
```solidity
interface IGame {
    function placeBet(address token, uint256 amount, bytes calldata data) external payable returns (uint256 betId);
    function getBet(uint256 betId) external view returns (address player, address token, uint256 amount, bool resolved);
}
```

### Randomness Provider (Chainlink VRF)
- Chainlink VRF V2.5 (recommended).
- Provider holds subscription id, keyHash, callbackGasLimit.
- Only registered games can request randomness.
- Fulfill calls game’s `rawFulfillRandomness`.

Key functions:
```solidity
function requestRandomness(uint32 numWords) external returns (uint256 requestId);
function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external;
```

### Treasury
- Holds ETH/ERC-20; enforce max exposure (optional).
- House edge in basis points (bps).
- Exposes `collect` and `payout` for games only.
- Use ReentrancyGuard in payout.

Key functions:
```solidity
function collect(address token, address from, uint256 amount) external;
function payout(address token, address to, uint256 amount) external;
function setMinMaxBet(address token, uint256 min, uint256 max) external;
function setHouseEdgeBps(uint256 bps) external;
```

### LotteryGame
- Time-based draws; users buy tickets before drawTime.
- On close, requests randomness; on fulfill, selects winner.
- Supports ETH and ERC-20 ticket payments.

Core flow:
- `buyTickets(token, amount, count)`
- `closeRound()`
- `fulfillRound(requestId, randomWords)`

Key functions:
```solidity
function buyTickets(address token, uint256 ticketPrice, uint256 count) external payable returns (uint256 roundId);
function closeRound() external;
function fulfillRound(uint256 requestId, uint256[] calldata randomWords) external;
```

### DiceGame
- Player chooses target and stake; odds derived from target.
- Requests randomness for each bet; resolves immediately on fulfill.

Key functions:
```solidity
function placeBet(address token, uint256 amount, uint256 target) external payable returns (uint256 betId);
function resolveBet(uint256 requestId, uint256[] calldata randomWords) external;
```

### Anti-Cheating Extensions (Optional)
- Commitment scheme for user inputs (e.g., seed).
- Time-locked reveal for lottery seed contribution.
- Slashing on reveal failure (for user-seeded games).

### Events (Core)
- `RandomnessRequested(uint256 requestId, address game)`
- `RandomnessFulfilled(uint256 requestId, address game)`
- `BetPlaced(uint256 betId, address player, address token, uint256 amount)`
- `BetResolved(uint256 betId, address player, uint256 payout)`
- `RoundClosed(uint256 roundId, uint256 requestId)`
- `RoundSettled(uint256 roundId, address winner, uint256 payout)`

### Upgrade Strategy
- Use a registry to map games and allow replacing game contracts.
- Treasury stays immutable; games are replaceable.

### Notes on MEV and Fairness
- No on-chain source of randomness used directly.
- Bets use VRF; results are verified via fulfill callback.
- Use per-bet commits if user-provided seeds are added later.

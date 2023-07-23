//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /*events*/
    //same as in Raffle.sol
    event EnteredRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player"); //cheat to create a labled address
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,

        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN); // == on any raffle state the enum variable should be OPEN
    }

    ///////////////////////
    //enter Raffle       //
    ///////////////////////
    function testRaffleRevertsWhenYouDontPayEnough() public {
        //Arrange
        vm.prank(PLAYER);
        //Act / Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle(); //not sending any value -> expect an error
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0); //not needed?
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        //i expect the NEXT emit to happen
        //first true because one expected
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER); //emite the event i expect to happen
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //performupkeep sets raffle to calculating state
        //let enough time pass -> forge cheat: vm.warp sets block to timestamp // vm.roll sets blocknumber
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        //check that nobody can enter now that raffle is calculating
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    ///////////////////////
    //checkUpkeep        //
    ///////////////////////
    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        //Arrange
        vm.warp(block.timestamp + interval + 1); //make time pass
        vm.roll(block.number + 1); //make block pass

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        //Assert
        assert(!upkeepNeeded); //assert not false -> true
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); //make time pass
        vm.roll(block.number + 1); //make block pass
        raffle.performUpkeep(""); //should put it into CALCULATING state

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        //Assert
        assert(upkeepNeeded == false); //since it is CALCULATING upkeepNeeded should be false . same as assert(!UpkeepNeeded)
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval - 1); //make less time pass

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //Assert
        assert(upkeepNeeded == false); //since enough time has not passed
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); //make less time pass
        vm.roll(block.number + 1); //make block pass

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //Assert
        assert(upkeepNeeded);
    }

    ///////////////////////
    //performUpkeep      //
    ///////////////////////

    //MY TEST ATTEMPT
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); //make time pass
        vm.roll(block.number + 1); //make block pass

        //Act / Assert
        //there is no expectNOrevert, so no assert needed.
        //test fails if performupkeep reverts
        raffle.performUpkeep(""); //should put it into CALCULATING state -> no upkeep needed
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        //Arrange
        //upkeepneeded starts out as false
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;
        // act / assert
        //expect a revert with those 3 parameters, could test all 3
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); //make time pass
        vm.roll(block.number + 1); //make block pass
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        //Arrange

        {
            //Act
            vm.recordLogs(); //records all emmitted events
            raffle.performUpkeep("");
            Vm.Log[] memory entries = vm.getRecordedLogs(); //vm type import needed for vm.log
            //need to figure out which spot my emmit is, forge test --debug can help. cheating: patrick said it is the 2nd event (first event = randomwordsrequested, 2nd= requestedrafflewinner)
            bytes32 requestId = entries[1].topics[1]; //[0] would be the first event, [1] the second
            Raffle.RaffleState rState = raffle.getRaffleState();
            //assert
            assert(uint256(requestId) > 0); //requestId is a random number, so it should be > 0
            assert(uint256(rState) == 1); //raffle state should be 1 = calculating
        }
    }

    ///////////////////////
    //fulfillRandomWords //
    ///////////////////////

    //if not anvil chain, skip this test
    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    //skip this test in non anvil chains, since VRFCoordinatorV2 (real one) takes different parameters than the mock
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEnteredAndTimePassed skipFork {
        //Arrange
        //no upkeep called before
        //Act / Assert
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    //pretending to be chainlink VRF in this test, SKIP outside of anvil again
    function testFulfullRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEnteredAndTimePassed
        skipFork
    {
        //Arrange
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i)); // generates different addresses for each player
            hoax(player, STARTING_USER_BALANCE); //hoax = prank+deal
            raffle.enterRaffle{value: entranceFee}();
        }
        //Act
        uint256 prize = entranceFee * (additionalEntrants + 1); //previous balance of winner
        vm.recordLogs(); //records all emmitted events
        raffle.performUpkeep(""); //emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs(); //counts everything as bytes32, so need to convert to uint256 inside the chainlinkmock below
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        //pretend to be chainlink VRF to get random number & pick winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );
        //Assert
        assert(uint256(raffle.getRaffleState()) == 0); //raffle state should be 0 = open
        assert(raffle.getRecentWinner() != address(0)); //should have a recent winner after we picked it above
        assert(raffle.getLengthOfPlayers() == 0); //check if players array is reset
        assert(previousTimeStamp < raffle.getLastTimeStamp()); //check if last timestamp is reset
        console.log("recent winner is :", raffle.getRecentWinner().balance);
        console.log("prize + starting :", prize + STARTING_USER_BALANCE);
        assert(
            raffle.getRecentWinner().balance ==
                STARTING_USER_BALANCE + prize - entranceFee
        ); //check how much money the winner got
    }
}

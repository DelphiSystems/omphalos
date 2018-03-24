pragma solidity ^0.4.18;

contract Pylon {
    function get(address oracle, address register) public constant returns (bytes32 value);
    function getStatus(address oracle, address register) public constant returns (uint status);
}

/*************************************************************************\
 *   Omphalos: Binary Prediction Market
 *
 *   Prediction market supporting binary outcomes (true or false)
 *
 *   Basic Proportional Model: predictors who chose the correct outcome
 *   receive claim to cumulative predicted stake upon market settlement,
 *   proportional to their correctly staked amount.
 *
\*************************************************************************/
contract BinaryPredictionMarket {
    /******************\
     *  Market State  *
     ********************************************************************\
     *  @dev The different possible market states:
     *       Active: predictions can be made
     *       Locked: predictions/claims cannot be made
     *       Finalized: claims can be made
    \********************************************************************/
    enum State { Active, Locked, Finalized }

    address public pylon;                               // Pylon registry contract
    address public oracle;                              // Oracle in pylon registry
    uint public totalMarketStake;                       // Cumulative value staked on predictions
    mapping (address => uint) public availableBalances; // Depositable/withrawable user accounts
    mapping (bool => Prediction) public predictions;    // Map true/false values to user predictions
    bool public outcome;                                // Final outcome (whether true or false)

    /************\
     *  Events  *
    \************/
    event Stake(address indexed _from, bool _prediction, uint _amount);  // User stakes prediction
    event Deposit(address indexed _from, uint _amount);                  // User makes deposit
    event Withdrawal(address indexed _to, uint _amount);                 // User makes withdrawal
    event Claim(address indexed _to, bool _prediction, uint _amount);    // User claims winnings
    event Settled(bool _outcome);                                        // Outcome settled (pylon pull)
    
    /*************\
     *  Structs  *
     ********************************************************************\
     *  Prediction
     *  @dev Represents a specific binary outcome;
     *       Tracks both individual stakes and cumulative outcome stake
    \********************************************************************/
    struct Prediction {
        mapping (address => uint) stakes;
        uint totalPredictionStake;
    }

    /**************\
     *  Modifiers
    \**************/
    modifier onState(State s) {
        // Make sure relevant pylon registry is in the correct state
        require(State(Pylon(pylon).getStatus(oracle, this)) == s);
        _;
    }

    /**********************\
     *  Public functions
     ********************************************************\
     *  @dev Constructor
     *  @param _pylon Address of pylon registry pulled from
     *  @param _oracle Address of oracle in pylon registry
    \********************************************************/
    function BinaryPredictionMarket(address _pylon, address _oracle) public {
        pylon = _pylon;
        oracle = _oracle;
    }

    /**************************\
     *  @dev Deposit function
    \**************************/
    function () public payable {
        // Credit user's available balance
        availableBalances[msg.sender] += msg.value;

        // Emit Deposit event
        emit Deposit(msg.sender, msg.value);
    }

    /*********************************************\
     *  @dev Withdrawal function
     *  @param _amount Withdrawal value (in wei)
     *  Withdraws from caller's availableBalance
    \*********************************************/
    function withdraw(uint _amount) public {
        // Ensure user has enough available balance to cover the withdrawal
        if (_amount == 0 || availableBalances[msg.sender] == 0 || _amount > availableBalances[msg.sender]) {
            revert();
        }

        // Decrement user's available balance before issuing funds
        availableBalances[msg.sender] -= _amount;

        // Send withdrawal
        if (msg.sender.send(_amount)) {
            // Emit Withdrawal event
            emit Withdrawal(msg.sender, _amount);
        }
    }

    /***************************************************************\
     *  @dev Shortcut function to withdraw entire availableBalance
    \***************************************************************/
    function withdrawAll() public {
        // Retrieve user's available balance
        uint withdrawal = availableBalances[msg.sender];

        // Don't bother trying to withdraw if account is empty
        if (withdrawal == 0) {
            revert();
        }

        // Decrement user's available balance before issuing funds
        availableBalances[msg.sender] = 0;

        // Send full withdrawal
        if (msg.sender.send(withdrawal)) {
            // Emit Withdrawal event
            emit Withdrawal(msg.sender, withdrawal);
        }
    }

    /***************************************************************\
     *  @dev Prediction/settlement function
     *  @param _outcome Prediction (or result)
     *  @param _amount Stake value (in wei)
     *  When called by a user, stakes a prediction
    \***************************************************************/
    function choose(bool _outcome, uint _amount) public {
        predict(_outcome, _amount);
    }

    /********************************************************************\
     *  @dev Claim function for users to collect on winning predictions
     *  Can only be called after a market is finalized by its oracle
     *  (which necessarily means that outcome is set)
    \********************************************************************/
    function claim() public onState(State.Finalized) {
        // Retrieve the total stake that the user assigned to the correct prediction
        uint userStake = getCorrectStake(msg.sender);
        if (userStake == 0) {
            revert();
        }

        // Reward user proportionally
        uint reward = totalMarketStake*userStake / predictions[outcome].totalPredictionStake;

        // Decrement user's correctly-staked balance first
        predictions[outcome].stakes[msg.sender] = 0;

        // Credit winnings to user's available balance
        availableBalances[msg.sender] += reward;

        // Emit Claim event
        emit Claim(msg.sender, outcome, reward);
    }

    /************************\
     *  Accessor functions  *
     ************************************************************\
     *  @dev Get value user has staked on a prediction outcome
     *  @param _predictor User whose stake is being retrieved
     *  @param _prediction Binary prediction value
     *  @return Prediction stake value (in wei)
    \************************************************************/
    function getStake(address _predictor, bool _prediction) public view returns (uint) {
        return predictions[_prediction].stakes[_predictor];
    }

    /***********************************************************\
     *  @dev Get value user has staked on the correct outcome
     *  @param _predictor User whose stake is being retrieved
     *  @return Prediction stake value (in wei)
    \***********************************************************/
    function getCorrectStake(address _predictor) public view onState(State.Finalized) returns (uint) {
        return predictions[outcome].stakes[_predictor];
    }

    /***********************\
     *  Private functions  *
     *********************************************************\
     *  @dev Predict function (helper function for choose())
     *  @param _outcome User's binary prediction value
     *  @param _amount Prediction stake value (in wei)
     *
     *  Only callable by non-oracle users
    \*********************************************************/
    function predict(bool _outcome, uint _amount) private onState(State.Active) {
        // Ensure funds are available
        if (_amount == 0 || availableBalances[msg.sender] < _amount) {
            revert();
        }

        // Decrement user's available balance first
        availableBalances[msg.sender] -= _amount;
        // Increment user's staked balance on outcome
        predictions[_outcome].stakes[msg.sender] += _amount;
        // Increment outcome's total staked balance
        predictions[_outcome].totalPredictionStake += _amount;
        // Increment market's total staked balance
        totalMarketStake += _amount;

        // Emit Stake (user prediction) event
        emit Stake(msg.sender, _outcome, _amount);
    }

    /**********************************************************\
     *  @dev Settle function (pulls from pylon registry)
    \**********************************************************/
    function settle() public onState(State.Finalized) {
        // Do not bother trying to settle an empty market
        if (totalMarketStake == 0) {
            revert();
        }

        // Set correct outcome value
        if (Pylon(pylon).get(oracle, this) > 0) {
            // Anything other than zero is interpreted as true
            outcome = true;
        } else {
            // Technically unnecessary operation, but aids with readability
            outcome = false;
        }

        // Emit Settled (oracle input) event
        emit Settled(outcome);
    }
}
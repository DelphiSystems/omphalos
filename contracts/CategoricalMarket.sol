pragma solidity ^0.4.18;

contract Pylon {
    function get(address oracle, bytes32 register) public constant returns (bytes32 value);
    function getStatus(address oracle, bytes32 register) public constant returns (uint status);
}

/*************************************************************************\
 *   Omphalos: Categorical Prediction Market
 *
 *   Prediction market supporting categorical outcomes
 *
 *   Basic Proportional Model: predictors who chose the correct category
 *   receive claim to cumulative predicted stake upon market settlement,
 *   proportional to their correctly staked amount.
 *
\*************************************************************************/
contract CategoricalPredictionMarket {
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
    bytes32 public register;                            // Pylon register field
    uint public totalMarketStake;                       // Cumulative value staked on predictions
    mapping (address => uint) public availableBalances; // Depositable/withrawable user accounts
    mapping (bytes32 => Prediction) public predictions; // Map of categories to user predictions
    bytes32 public outcome;                             // Final outcome (correct category)

    /************\
     *  Events  *
    \************/
    event Stake(address indexed _from, bytes32 _prediction, uint _amount);  // User stakes prediction
    event Deposit(address indexed _from, uint _amount);                     // User makes deposit
    event Withdrawal(address indexed _to, uint _amount);                    // User makes withdrawal
    event Claim(address indexed _to, bytes32 _prediction, uint _amount);    // User claims winnings
    event Settled(bytes32 _outcome);                                        // Outcome settled (pylon pull)

    /*************\
     *  Structs  *
     *********************************************************************\
     *  Prediction
     *  @dev Represents a specific categorical outcome;
     *       Tracks both individual stakes and cumulative category stake
    \*********************************************************************/
    struct Prediction {
        mapping (address => uint) stakes;
        uint totalPredictionStake;
    }

    /**************\
     *  Modifiers
    \**************/
    modifier onState(State s) {
        // Make sure relevant pylon registry is in the correct state
        require(State(Pylon(pylon).getStatus(oracle, register)) == s);
        _;
    }

    /**********************\
     *  Public functions
     ********************************************************\
     *  @dev Constructor
     *  @param _pylon Address of pylon registry pulled from
     *  @param _oracle Address of oracle in pylon registry
     *  @param _register Register field in pylon contract
     \********************************************************/
    function CategoricalPredictionMarket(address _pylon, address _oracle, bytes32 _register) public {
        pylon = _pylon;
        oracle = _oracle;
        register = _register;
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
     *  When called by a user, stakes a categorical prediction
     *  Can optionally include a deposit for an all-in-one call
    \***************************************************************/
    function choose(bytes32 _outcome, uint _amount) public payable {
        // Optional deposit before prediction
        if (msg.value > 0) {
            // Credit user's available balance
            availableBalances[msg.sender] += msg.value;

            // Emit Deposit event
            emit Deposit(msg.sender, msg.value);
        }

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
     *  @dev Get value user has staked on a prediction category
     *  @param _predictor User whose stake is being retrieved
     *  @param _prediction Categorical prediction value
     *  @return Prediction stake value (in wei)
    \************************************************************/
    function getStake(address _predictor, bytes32 _prediction) public view returns (uint) {
        return predictions[_prediction].stakes[_predictor];
    }

    /***********************************************************\
     *  @dev Get value user has staked on the correct category
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
     *  @param _outcome User's categorical prediction value
     *  @param _amount Prediction stake value (in wei)
     *
     *  Only callable by non-oracle users
    \*********************************************************/
    function predict(bytes32 _outcome, uint _amount) private onState(State.Active) {
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

    /********************************************************\
     *  @dev Settle function (pulls from pylon registry)
    \********************************************************/
    function settle() public onState(State.Finalized) {
        // Do not bother trying to settle an empty market
        if (totalMarketStake == 0) {
            revert();
        }

        // Set correct outcome value
        outcome = Pylon(pylon).get(oracle, register);

        // Emit Settled (oracle input) event
        emit Settled(outcome);
    }
}
pragma solidity ^0.4.18;

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
    address public oracle;                              // Outcome data provider
    uint public totalMarketStake;                       // Cumulative value staked on predictions
    mapping (address => uint) public availableBalances; // Depositable/withrawable user accounts
    mapping (bytes32 => Prediction) public predictions; // Map of categories to user predictions
    bool public settled;                                // Has the oracle finalized the outcome?
    bytes32 public outcome;                             // Final outcome (correct category)

    /************\
     *  Events  *
    \************/
    event Stake(address indexed _from, bytes32 _prediction, uint _amount);  // User stakes prediction
    event Deposit(address indexed _from, uint _amount);                     // User makes deposit
    event Withdrawal(address indexed _to, uint _amount);                    // User makes withdrawal
    event Claim(address indexed _to, bytes32 _prediction, uint _amount);    // User claims winnings
    event Settled(bytes32 _outcome);                                        // Oracle settles outcome

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
    modifier afterSettled() {
        require(settled);
        _;
    }

    modifier beforeSettled() {
        require(!settled);
        _;
    }

    /**********************\
     *  Public functions
     ********************************************************\
     *  @dev Constructor
     *  @param _oracle Address of oracle linked to contract
    \********************************************************/
    function CategoricalPredictionMarket(address _oracle) public {
        // Link oracle to contract
        oracle = _oracle;
    }

    /**************************\
     *  @dev Deposit function
    \**************************/
    function () public payable {
        // Credit user's available balance
        availableBalances[msg.sender] += msg.value;

        // Fire Deposit event
        Deposit(msg.sender, msg.value);
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
            // Fire Withdrawal event
            Withdrawal(msg.sender, _amount);
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
            // Fire Withdrawal event
            Withdrawal(msg.sender, withdrawal);
        }
    }

    /***************************************************************\
     *  @dev Prediction/settlement function
     *  @param _outcome Prediction (or result)
     *  @param _amount Stake value (in wei)
     *  When called by a user, stakes a categorical prediction
     *  When called by oracle, finalizes market to _outcome value
     *  Note: _amount is ignored when function is called by oracle
    \***************************************************************/
    function choose(bytes32 _outcome, uint _amount) public {
        if (msg.sender == oracle) {
            settle(_outcome);
        } else {
            predict(_outcome, _amount);
        }
    }

    /********************************************************************\
     *  @dev Claim function for users to collect on winning predictions
     *  Can only be called after a market is settled by its oracle
     *  (which necessarily means that outcome is set)
    \********************************************************************/
    function claim() public afterSettled {
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

        // Fire Claim event
        Claim(msg.sender, outcome, reward);
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
    function getCorrectStake(address _predictor) public view afterSettled returns (uint) {
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
    function predict(bytes32 _outcome, uint _amount) private beforeSettled {
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

        // Fire Stake (user prediction) event
        Stake(msg.sender, _outcome, _amount);
    }

    /********************************************************\
     *  @dev Settle function (helper function for choose())
     *  @param _outcome User's categorical prediction value
     *  Only callable by linked oracle
    \********************************************************/
    function settle(bytes32 _outcome) private beforeSettled {
        // Do not bother trying to settle an empty market
        if (totalMarketStake == 0) {
            revert();
        }

        // Set correct outcome value
        outcome = _outcome;
        // Finalize market
        settled = true;

        // Fire Settled (oracle input) event
        Settled(_outcome);
    }
}
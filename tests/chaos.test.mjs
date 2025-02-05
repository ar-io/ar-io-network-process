// import { describe, it } from 'node:test';
// import { getBalances } from './helpers.mjs';

// describe('Chaos', async () => {
//   it('is tolerated', async () => {});
// });

// // Convert the following Lua code into a JSON array whose values are the values of the lua table:
// /*
// local ActionMap = {
// 	-- reads
// 	Info = "Info",
// 	TotalSupply = "Total-Supply", -- for token.lua spec compatibility, gives just the total supply (circulating + locked + staked + delegated + withdraw)
// 	TotalTokenSupply = "Total-Token-Supply", -- gives the total token supply and all components (protocol balance, locked supply, staked supply, delegated supply, and withdraw supply)
// 	State = "State",
// 	Transfer = "Transfer",
// 	Balance = "Balance",
// 	Balances = "Balances",
// 	DemandFactor = "Demand-Factor",
// 	DemandFactorInfo = "Demand-Factor-Info",
// 	DemandFactorSettings = "Demand-Factor-Settings",
// 	-- EPOCH READ APIS
// 	Epochs = "Epochs",
// 	Epoch = "Epoch",
// 	EpochSettings = "Epoch-Settings",
// 	PrescribedObservers = "Epoch-Prescribed-Observers",
// 	PrescribedNames = "Epoch-Prescribed-Names",
// 	Observations = "Epoch-Observations",
// 	Distributions = "Epoch-Distributions",
// 	--- Vaults
// 	Vault = "Vault",
// 	Vaults = "Vaults",
// 	CreateVault = "Create-Vault",
// 	VaultedTransfer = "Vaulted-Transfer",
// 	ExtendVault = "Extend-Vault",
// 	IncreaseVault = "Increase-Vault",
// 	-- GATEWAY REGISTRY READ APIS
// 	Gateway = "Gateway",
// 	Gateways = "Gateways",
// 	GatewayRegistrySettings = "Gateway-Registry-Settings",
// 	Delegates = "Delegates",
// 	JoinNetwork = "Join-Network",
// 	LeaveNetwork = "Leave-Network",
// 	IncreaseOperatorStake = "Increase-Operator-Stake",
// 	DecreaseOperatorStake = "Decrease-Operator-Stake",
// 	UpdateGatewaySettings = "Update-Gateway-Settings",
// 	SaveObservations = "Save-Observations",
// 	DelegateStake = "Delegate-Stake",
// 	RedelegateStake = "Redelegate-Stake",
// 	DecreaseDelegateStake = "Decrease-Delegate-Stake",
// 	CancelWithdrawal = "Cancel-Withdrawal",
// 	InstantWithdrawal = "Instant-Withdrawal",
// 	RedelegationFee = "Redelegation-Fee",
// 	--- ArNS
// 	Record = "Record",
// 	Records = "Records",
// 	BuyRecord = "Buy-Record", -- TODO: standardize these as `Buy-Name` or `Upgrade-Record`
// 	UpgradeName = "Upgrade-Name", -- TODO: may be more aligned to `Upgrade-Record`
// 	ExtendLease = "Extend-Lease",
// 	IncreaseUndernameLimit = "Increase-Undername-Limit",
// 	ReassignName = "Reassign-Name",
// 	ReleaseName = "Release-Name",
// 	ReservedNames = "Reserved-Names",
// 	ReservedName = "Reserved-Name",
// 	TokenCost = "Token-Cost",
// 	CostDetails = "Get-Cost-Details-For-Action",
// 	GetRegistrationFees = "Get-Registration-Fees",
// 	ReturnedNames = "Returned-Names",
// 	ReturnedName = "Returned-Name",
// 	AllowDelegates = "Allow-Delegates",
// 	DisallowDelegates = "Disallow-Delegates",
// 	Delegations = "Delegations",
// 	-- PRIMARY NAMES
// 	RemovePrimaryNames = "Remove-Primary-Names",
// 	RequestPrimaryName = "Request-Primary-Name",
// 	PrimaryNameRequest = "Primary-Name-Request",
// 	PrimaryNameRequests = "Primary-Name-Requests",
// 	ApprovePrimaryNameRequest = "Approve-Primary-Name-Request",
// 	PrimaryNames = "Primary-Names",
// 	PrimaryName = "Primary-Name",
// }
// */
// let nextArweaveRecipient = () => {
//   // Generate 32 bytes of random data (256 bits)
//   const randomBuffer = crypto.randomBytes(32);

//   // Encode to base64url format
//   let base64url = randomBuffer
//     .toString('base64') // Convert to base64 string
//     .replace(/\+/g, '-') // Replace '+' with '-'
//     .replace(/\//g, '_') // Replace '/' with '_'
//     .replace(/=+$/, ''); // Remove trailing '=' characters

//   // Ensure the string is exactly 43 characters long
//   return base64url.slice(0, 43);
// };
// let nextEthereumAddress = () => {
//   // Generate 20 bytes of random data (160 bits)
//   const randomBuffer = crypto.randomBytes(20);

//   // Encode to hex format
//   let hex = randomBuffer.toString('hex');

//   // Ensure the string is exactly 40 characters long
//   return hex;
// };

// let nextAddress = () => {
//   // A random choice between an Arweave recipient and an Ethereum address
//   return Math.random() < 0.5 ? nextArweaveRecipient() : nextEthereumAddress();
// };

// const commands = {
//   Info: {},
//   'Total-Supply': {},
//   'Total-Token-Supply': {},
//   Transfer: {
//     Reasonable: async () => {
//       const balances = await getBalances();
//       const sender = balances[Math.floor(Math.random() * balances.length)];
//       const recipient = nextAddress();
//     },
//   },
//   // 'Balance',
//   // 'Balances',
//   // 'Demand-Factor',
//   // 'Demand-Factor-Info',
//   // 'Demand-Factor-Settings',
//   // 'Epochs',
//   // 'Epoch',
//   // 'Epoch-Settings',
//   // 'Epoch-Prescribed-Observers',
//   // 'Epoch-Prescribed-Names',
//   // 'Epoch-Observations',
//   // 'Epoch-Distributions',
//   // 'Vault',
//   // 'Vaults',
//   // 'Create-Vault',
//   // 'Vaulted-Transfer',
//   // 'Extend-Vault',
//   // 'Increase-Vault',
//   // 'Gateway',
//   // 'Gateways',
//   // 'Gateway-Registry-Settings',
//   // 'Delegates',
//   // 'Join-Network',
//   // 'Leave-Network',
//   // 'Increase-Operator-Stake',
//   // 'Decrease-Operator-Stake',
//   // 'Update-Gateway-Settings',
//   // 'Save-Observations',
//   // 'Delegate-Stake',
//   // 'Redelegate-Stake',
//   // 'Decrease-Delegate-Stake',
//   // 'Cancel-Withdrawal',
//   // 'Instant-Withdrawal',
//   // 'Redelegation-Fee',
//   // 'Record',
//   // 'Records',
//   // 'Buy-Record',
//   // 'Upgrade-Name',
//   // 'Extend-Lease',
//   // 'Increase-Undername-Limit',
//   // 'Reassign-Name',
//   // 'Release-Name',
//   // 'Reserved-Names',
//   // 'Reserved-Name',
//   // 'Token-Cost',
//   // 'Get-Cost-Details-For-Action',
//   // 'Get-Registration-Fees',
//   // 'Returned-Names',
//   // 'Returned-Name',
//   // 'Allow-Delegates',
//   // 'Disallow-Delegates',
//   // 'Delegations',
//   // 'Remove-Primary-Names',
//   // 'Request-Primary-Name',
//   // 'Primary-Name-Request',
//   // 'Primary-Name-Requests',
//   // 'Approve-Primary-Name-Request',
//   // 'Primary-Names',
//   // 'Primary-Name',
// };

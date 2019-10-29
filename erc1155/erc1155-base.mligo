#include "erc1155.mligo"

(*  owner -> operator set *)
type approvals = (address, address set) big_map

let set_approval_for_all (param : set_approval_for_all_param) (approvals : approvals) : approvals =
  let operators = match Map.find_opt sender approvals with
    | Some(ops) -> ops
    | None      -> (Set.empty : address set)
  in
  let new_operators = 
    if param.approved
    then Set.add param.operator operators
    else Set.remove param.operator operators
  in
    if Set.size new_operators = 0p
    then  Map.remove sender approvals
    else Map.update sender (Some new_operators) approvals
  

let is_approved_for_all (param : is_approved_for_all_param) (approvals : approvals) : operation = 
  let req = param.is_approved_for_all_request in
  let operators = Map.find_opt req.owner approvals in
  let result = match operators with
    | None      -> false
    | Some ops  -> Set.mem req.operator ops
  in
  param.approved_view (req, result)


let max_tokens = 4294967295p  (* 2^32-1 *)
let owner_offset = 4294967296p  (* 2^32 *)

type balances = (nat, nat) map //TODO: change to big_map
type owner_lookup = {
  owner_count : nat;
  owners: (address, nat) map //TODO: change to big_map
}

type balance_storage = {
  owners : owner_lookup;
  balances : balances;  
}

(* return updated storage and newly added owner id *)
let add_owner (owner : address) (s : owner_lookup) : (nat * owner_lookup) =
  let owner_id  = s.owner_count + 1p in
  let os = Map.add owner owner_id s.owners in
  let new_s = 
    { 
      owner_count = owner_id;
      owners = os;
    } in
  (owner_id, new_s)

(* gets existing owner id. If owner does not have one, creates a new id and adds it to an owner_lookup *)
let ensure_owner_id (owner : address) (s : owner_lookup): (nat * owner_lookup) =
  let owner_id = Map.find_opt owner s.owners in
  match owner_id with
    | Some id -> (id, s)
    | None    -> add_owner owner s

let pack_balance_key (key : balance_request) (s : owner_lookup) : nat =
  let owner_id = Map.find_opt key.owner s.owners in
  match owner_id with
    | None    -> (failwith("No such owner") : nat)
    | Some id -> 
        if key.token_id > max_tokens
        then (failwith("provided token ID is out of allowed range") : nat)
        else key.token_id + (id * owner_offset)
 
let get_balance (key : nat) (b : balances) : nat =
  let bal : nat option = Map.find_opt key b in
  match bal with
    | None    -> 0p
    | Some b  -> b

let get_balance_req (r : balance_request) (s : balance_storage) : nat =
  let balance_key = pack_balance_key r s.owners in
  get_balance balance_key s.balances



let balance_of (param : balance_of_param) (s : balance_storage) : operation =
  let bal = get_balance_req param.balance_request s in
  param.balance_view (param.balance_request, bal)



let balance_of_batch (param : balance_of_batch_param) (s : balance_storage)   : operation =
  let to_balance = fun (r: balance_request) ->
    let bal = get_balance_req r s in
    (r, bal) 
  in
  let requests_2_bals = List.map param.balance_request to_balance in
  param.balance_view requests_2_bals

let transfer_balance (from_key : nat) (to_key : nat) (amt : nat) (s : balances) : balances = 
  let from_bal = get_balance from_key s in
  if from_bal < amt
  then (failwith ("Insufficient balance") : balances)
  else
    let fbal = abs (from_bal - amt) in
    let s1 = 
      if fbal = 0p 
      then Map.remove from_key s
      else Map.update from_key (Some fbal) s 
    in
    let to_bal = get_balance to_key s1 in
    let tbal = to_bal + amt in
    let s2 = Map.update to_key (Some tbal) s1 in
    s2

let safe_transfer_from (param : safe_transfer_from_param) (s : balance_storage) : (operation  list) * balance_store = 
  let from_key  = pack_balance_key { owner = param.from_; token_id = param.token_id; } s.owners in
  let to_key    = pack_balance_key { owner = param.to_;   token_id = param.token_id; } s.owners in
  let new_balances = transfer_balance from_key to_key param.amount s.balances in
  let new_store: balance_storage = {
      owners = s.owners;
      balances = new_balances;
    } in
  // let receiver : erc1155_token_receiver contract =  Operation.get_contract param.to_ in
  // let ops = match receiver with
  //   None    -> ([] : operation list)
  //   Some c  -> 
      // let p : on_erc1155_received_param = {
      //   operator = sender;
      //   from_ = Some param.from_;
      //   token_id = param.token_id;
      //   amount = param.amount;
      //   data = param.data;
      // } in
      // let op = Operartion.transaction p 0mutez c in
      //[op] in
  // (ops, new)
  (([] : operation list), new_store)

  // let safe_transfer_from (s: )


let base_test (p : unit) = unit
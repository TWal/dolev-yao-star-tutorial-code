module DY.Extend

open Comparse
open DY.Core
open DY.Lib
open DY.Core.Trace.Base

val event_exists_grows:
  #label_t:Type -> 
  tr1:trace_ label_t -> tr2:trace_ label_t -> 
  e:trace_event_ label_t ->
  Lemma
  (requires
    tr1 <$ tr2 /\ event_exists tr1 e
  )
  (ensures
    event_exists tr2 e
  )
let event_exists_grows tr1 tr2 e =  ()

val last_entry_exists:
  #label_t:Type ->
  tr:trace_ label_t ->
  Lemma
    (requires Snoc? tr )
    (ensures (
       let Snoc _ last = tr in
       event_exists tr last
    ))
    [SMTPat (Snoc? tr)]
let last_entry_exists tr = 
  let Snoc _ last = tr in
  assert(event_at tr (length tr - 1) last)


val get_state_aux_state_was_set:
  prin:principal -> sess_id:state_id -> tr:trace ->
  Lemma
  (ensures (
    match get_state_aux prin sess_id tr with
    | None -> True
    | Some content -> 
          state_was_set tr prin sess_id content
  ))
let rec get_state_aux_state_was_set prin sess_id tr =
   match tr with
  | Nil -> ()
  | Snoc tr_init (SetState prin' sess_id' content) -> (
    if prin = prin' && sess_id = sess_id' 
    then ()
    else get_state_aux_state_was_set prin sess_id tr_init
  )
  | Snoc tr_init _ ->
         get_state_aux_state_was_set prin sess_id tr_init

val get_state_state_was_set:
  prin:principal -> sess_id:state_id -> tr:trace ->
  Lemma
  (ensures (
    let (opt_content, tr_out) = DY.Core.get_state prin sess_id tr in
    tr == tr_out /\ (
      match opt_content with
      | None -> True
      | Some content -> 
             state_was_set tr prin sess_id content
    )
  ))
  [SMTPat (DY.Core.get_state prin sess_id tr)]
let get_state_state_was_set prin sess_id tr =
  reveal_opaque (`%DY.Core.get_state) DY.Core.get_state;
  get_state_aux_state_was_set prin sess_id tr
  


/// Lookup the most recent state of a principal satisfying some property.
/// Returns the state and corresponding state id,
/// or `None` if no such state exists.

val lookup_state_aux: principal -> (bytes -> bool) -> trace -> option (bytes & state_id)
let rec lookup_state_aux prin p tr =
  match tr with
  | Nil -> None
  | Snoc rest (SetState prin' sid' cont') ->
      if prin' = prin && p cont'
      then Some (cont', sid')
      else lookup_state_aux prin p rest
  | Snoc rest _ -> lookup_state_aux prin p rest

val core_lookup_state: principal -> (bytes -> bool) -> traceful (option (bytes & state_id))
let core_lookup_state prin p =
  let* tr = get_trace in
  return (lookup_state_aux prin p tr)

/// If `lookup` returns some state,
/// this state satisfies the property used in the lookup.

val lookup_state_aux_state_was_set_and_prop:
  prin:principal -> p:(bytes -> bool) -> tr:trace ->
  Lemma
  (ensures (
    let opt_content = lookup_state_aux prin p tr in
      match opt_content with
      | None -> True
      | Some (content, sid) ->
               p content
             /\ state_was_set tr prin sid content
  ))
let rec lookup_state_aux_state_was_set_and_prop prin p tr =
  match tr with
  | Nil -> ()
  | Snoc tr_init _ ->
         lookup_state_aux_state_was_set_and_prop prin p tr_init

/// If `lookup` returns a state on a trace with `trace_invariant`,
/// the returned state additionally satisfies the state predicate.

val lookup_state_aux_state_invariant:
  {|protocol_invariants|} ->
  prin:principal -> p:(bytes -> bool) -> tr:trace ->
  Lemma
  (requires
    trace_invariant tr
  )
  (ensures (
    let opt_content = lookup_state_aux prin p tr in
      match opt_content with
      | None -> True
      | Some (content, sid) ->
               state_pred.pred tr prin sid content
             /\ p content
             /\ state_was_set tr prin sid content
  ))
let lookup_state_aux_state_invariant #invs prin p tr =
  lookup_state_aux_state_was_set_and_prop prin p tr;
  match lookup_state_aux prin p tr with
  | None -> ()
  | Some (content, sid) ->
    DY.Core.state_was_set_implies_pred tr prin sid content

/// lifting both properties from `_aux` to the `traceful` versions.

val core_lookup_state_state_was_set_and_prop:
  prin:principal -> p:(bytes -> bool) -> tr:trace ->
  Lemma
  (ensures (
    let (opt_content, tr_out) = core_lookup_state prin p tr in
    tr == tr_out /\
    (match opt_content with
     | None -> True
     | Some (content, sid) ->
              p content
            /\ state_was_set tr prin sid content
    )
  ))
  [SMTPat (core_lookup_state prin p tr)]
let core_lookup_state_state_was_set_and_prop prin p tr =
  lookup_state_aux_state_was_set_and_prop prin p tr


val lookup_state_state_invariant:
  {|invs:protocol_invariants|} ->
  prin:principal -> p:(bytes -> bool) -> tr:trace ->
  Lemma
  (requires
    trace_invariant tr
  )
  (ensures (
    let (opt_content, tr_out) = core_lookup_state prin p tr in
    tr == tr_out /\
    (match opt_content with
     | None -> True
     | Some (content, sid) ->
              state_pred.pred tr prin sid content
            /\ p content
            /\ state_was_set tr prin sid content
    )
  ))
  [SMTPat (core_lookup_state prin p tr); SMTPat (trace_invariant #invs tr)]
let lookup_state_state_invariant #invs prin p tr =
  lookup_state_aux_state_invariant prin p tr


// val tagged_state_was_set_grows:
//   tr1:trace -> tr2:trace ->
//   tag:string -> p:principal -> sid:state_id -> cont:bytes ->
//   Lemma
//   (requires
//      tr1 <$ tr2 /\ tagged_state_was_set tr1 tag p sid cont
//   )
//   (ensures
//     tagged_state_was_set tr2 tag p sid cont
//   )
// let tagged_state_was_set_grows tr1 tr2 tag p sid cont = 
//   reveal_opaque (`%tagged_state_was_set) tagged_state_was_set


/// Lookup the most recent tagged state for a principal that satisfys some property.
/// The property given as argument is on the _content_ of the state.

val lookup_tagged_state:
 string -> principal -> (bytes -> bool) -> traceful (option (bytes & state_id))
let lookup_tagged_state the_tag prin p =
  let p_ b =
    match parse tagged_state b with
    | None -> false
    | Some ({tag; content;}) -> tag = the_tag && p content in
  let*? (full_content_bytes, sid) = core_lookup_state prin p_ in
  match parse tagged_state full_content_bytes with
    | None -> return None
    | Some ({tag; content;}) ->
        if (tag = the_tag)
        then return (Some (content, sid))
        else return None


val get_tagged_state_state_was_set:
  tag:string -> 
  prin:principal -> sess_id:state_id -> tr:trace ->
  Lemma
  (ensures (
    let (opt_content, tr_out) = get_tagged_state tag prin sess_id tr in
    tr == tr_out /\ (
      match opt_content with
      | None -> True
      | Some content -> (
         tagged_state_was_set tr tag prin sess_id content
      )
    )
  )
  )
  [SMTPat (get_tagged_state tag prin sess_id tr)]
let get_tagged_state_state_was_set tag prin sess_id tr =
  reveal_opaque (`%get_tagged_state) (get_tagged_state);
  reveal_opaque (`%tagged_state_was_set) (tagged_state_was_set);
  let (opt_content, tr_out) = get_tagged_state tag prin sess_id tr in
  match opt_content with
  | None -> ()
  | Some cont -> (
    let (Some full_cont_bytes, _) = DY.Core.get_state prin sess_id tr in
    serialize_parse_inv_lemma #bytes tagged_state full_cont_bytes    
  )

val lookup_tagged_state_pred:
  tag:string ->
  prin:principal -> p:(bytes -> bool) -> tr:trace ->
  Lemma
  (ensures (
    let (opt_content, tr_out) = lookup_tagged_state tag prin p tr in
    tr == tr_out /\
    (match opt_content with
     | None -> True
     | Some (content,sid) ->
           p content
         /\ tagged_state_was_set tr tag prin sid content
    )
  ))
  [SMTPat (lookup_tagged_state tag prin p tr);
  ]
let lookup_tagged_state_pred the_tag prin p tr =
  let (opt_content, tr_out) = lookup_tagged_state the_tag prin p tr in
  match opt_content with
  | None -> ()
  | Some (cont, sid) -> (
  reveal_opaque (`%tagged_state_was_set) (tagged_state_was_set);
  let p_ b =
    match parse tagged_state b with
    | None -> false
    | Some ({tag; content;}) -> tag = the_tag && p content in
  let (Some (full_cont_bytes, sid), _) = core_lookup_state prin p_ tr in
  serialize_parse_inv_lemma #bytes tagged_state full_cont_bytes
  )

val lookup_tagged_state_invariant:
  {|protocol_invariants|} ->
  tag:string -> spred:local_bytes_state_predicate tag ->
  prin:principal -> p:(bytes -> bool) -> tr:trace ->
  Lemma
  (requires
    trace_invariant tr /\
    has_local_bytes_state_predicate (|tag, spred|)
  )
  (ensures (
    let (opt_content, tr_out) = lookup_tagged_state tag prin p tr in
    tr == tr_out /\
    (match opt_content with
     | None -> True
     | Some (content,sid) ->
           spred.pred tr prin sid content
         /\ p content
         /\ tagged_state_was_set tr tag prin sid content
    )
  ))
  [SMTPat (lookup_tagged_state tag prin p tr);
   SMTPat (trace_invariant tr);
   SMTPat (has_local_bytes_state_predicate (|tag, spred|))]
let lookup_tagged_state_invariant #invs the_tag spred prin p tr =
  reveal_opaque (`%has_local_bytes_state_predicate) (has_local_bytes_state_predicate);
  let (opt_content, tr_out) = lookup_tagged_state the_tag prin p tr in
  match opt_content with
  | None -> ()
  | Some (content,sid) -> (
      let p_ b =
        match parse tagged_state b with
        | None -> false
        | Some ({tag; content;}) -> tag = the_tag && p content in

      let (Some (l_cont, l_sid), _) = core_lookup_state prin p_ tr in
      serialize_parse_inv_lemma #bytes tagged_state l_cont;
      reveal_opaque (`%tagged_state_was_set) (tagged_state_was_set);

      let (Some (full_content_bytes, sid), tr) = core_lookup_state prin p_ tr in
      local_eq_global_lemma split_local_bytes_state_predicate_params state_pred.pred the_tag spred (tr, prin, sid, full_content_bytes) the_tag (tr, prin, sid, content)
     )

/// Lookup the most recent state of a principal that satisfys some property.

val lookup_state:
  #a:Type -> {|local_state a|} ->
  principal -> (a -> bool) -> traceful (option (a & state_id))
let lookup_state #a #ls prin p =
  let p_ b =
    match parse a b with
    | None -> false
    | Some x -> p x in
  let*? (content_bytes, sid) = lookup_tagged_state ls.tag prin p_ in
  match parse a content_bytes with
  | None -> return None
  | Some content -> return (Some (content,sid))


val lookup_state_pred:
  #a:Type -> {|ls:local_state a|} ->
  prin:principal -> p:(a -> bool) -> tr:trace ->
  Lemma
  (ensures (
    let (opt_content, tr_out) = lookup_state prin p tr in
    tr == tr_out /\
    (match opt_content with
     | None -> True
     | Some (content, sid) ->
          p content
          /\ DY.Lib.state_was_set tr prin sid content
    )
  ))
  [SMTPat (lookup_state #a #ls prin p tr);
   ]
let lookup_state_pred #a #ls prin p tr =
  let (opt_content, tr_out) = lookup_state prin p tr in
  match opt_content with
  | None -> ()
  | Some (content, sid) -> (
      let p_ b =
        match parse a b with
        | None -> false
        | Some x -> p x in
      let (Some (l_cont, l_sid), _) = lookup_tagged_state ls.tag prin p_ tr in
     serialize_parse_inv_lemma #bytes a l_cont;
     reveal_opaque (`%DY.Lib.state_was_set) (DY.Lib.state_was_set #a)
  )



val lookup_state_invariant:
  #a:Type -> {|local_state a|} ->
  {|protocol_invariants|} ->
  spred:local_state_predicate a ->
  prin:principal -> p:(a -> bool) -> tr:trace ->
  Lemma
  (requires
    trace_invariant tr /\
    has_local_state_predicate spred
  )
  (ensures (
    let (opt_content, tr_out) = lookup_state prin p tr in
    tr == tr_out /\
    (match opt_content with
     | None -> True
     | Some (content, sid) ->
         spred.pred tr prin sid content
         /\ p content
         /\ DY.Lib.state_was_set tr prin sid content
    )
  ))
  [SMTPat (lookup_state #a prin p tr);
   SMTPat (trace_invariant tr);
   SMTPat (has_local_state_predicate spred)]
let lookup_state_invariant #a #ls #invs spred prin p tr =
  let (opt_content, tr_out) = lookup_state prin p tr in
  match opt_content with
  | None -> ()
  | Some (content, sid) -> (
      let p_ b =
        match parse a b with
        | None -> false
        | Some x -> p x in
      let (Some (l_cont, l_sid), _) = lookup_tagged_state ls.tag prin p_ tr in
      serialize_parse_inv_lemma #bytes a l_cont;
      reveal_opaque (`%DY.Lib.state_was_set) (DY.Lib.state_was_set #a)
  )
::  btc-provider.hoon
::  Proxy that serves a BTC full node and ElectRS address indexer
::
::  Subscriptions: none
::  To Subscribers: /clients
::    current connection state
::    results/errors of RPC calls
::
/+  *btc-provider, dbug, default-agent
|%
+$  versioned-state
    $%  state-0
    ==
::
+$  state-0  [%0 =host-info whitelist=(set ship)]
::
+$  card  card:agent:gall
::
--
%-  agent:dbug
=|  state-0
=*  state  -
^-  agent:gall
=<
|_  =bowl:gall
+*  this      .
    def   ~(. (default-agent this %|) bowl)
    hc    ~(. +> bowl)
::
++  on-init
  ^-  (quip card _this)
  ~&  >  '%btc-provider initialized successfully'
  ::  ping every 30s to see whether connected to RPC
  ::
  `this(host-info [*credentials connected=%.n clients=*(set ship)], whitelist *(set ship))
++  on-save
  ^-  vase
  !>(state)
++  on-load
  |=  old-state=vase
  ^-  (quip card _this)
  ~&  >  '%btc-provider recompiled successfully '
  `this(state !<(versioned-state old-state))
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ::  Only allow clients/authorized to poke
  ::
  ?>  ?|((team:title our.bowl src.bowl) (is-client:hc src.bowl))
  =^  cards  state
    ?+  mark  (on-poke:def mark vase)
        %btc-provider-command
      ?>  (team:title our.bowl src.bowl)
      (handle-command:hc !<(command vase))
        %btc-provider-action
      (handle-action:hc !<(action vase))
    ==
  [cards this]
++  on-watch
  |=  pax=path
  ^-  (quip card _this)
  ?>  ?=([%clients *] pax)
  ?>  (is-whitelisted:hc src.bowl)
  ~&  >  "btc-provider: added client {<src.bowl>}"
  `this(clients.host-info (~(put in clients.host-info) src.bowl))
::
++  on-leave  on-leave:def
++  on-peek   on-peek:def
++  on-agent  on-agent:def
++  on-arvo
  |=  [=wire =sign-arvo]
  ^-  (quip card _this)
  ::  check for connectivity every 30 seconds with %ping
  ::
  ?:  ?=([%ping-timer *] wire)
    :_  this
    :~  :*  %pass  /ping/[(scot %da now.bowl)]  %agent
            [our.bowl %btc-provider]  %poke
            %btc-provider-action  !>([%ping ~])
        ==
        (start-ping-timer:hc ~s30)
    ==
  =^  cards  state
  ?+    +<.sign-arvo    (on-arvo:def wire sign-arvo)
      %http-response
      (handle-rpc-response:hc wire client-response.sign-arvo)
  ==
  [cards this]
::
++  on-fail   on-fail:def
--
::  helper core
|_  =bowl:gall
++  handle-command
  |=  comm=command
  ^-  (quip card _state)
  ?-  -.comm
      %set-credentials
    :-  ~[(start-ping-timer ~s30)]
    state(host-info [creds.comm connected=%.y clients=*(set ship)])
    ::
      %whitelist-clients
    `state(whitelist (~(uni in whitelist) clients.comm))
==
++  start-ping-timer
  |=  interval=@dr  ^-  card
  [%pass /ping-timer %arvo %b %wait (add now.bowl interval)]
::  only %ping works if we're not connected
::
++  handle-action
  |=  act=action
  |^  ^-  (quip card _state)
  ?:  ?&(?!(connected.host-info) ?!(=(-.act %ping)))
    ~&  >>>  "Not connected to RPC"
    [~[(send-update [%| [%not-connected 500]])] state]
  =/  ract=action:rpc
    ?-  -.act
        %watch-address
      [%erpc %get-address-utxos address.act]
      ::
        %ping
      [%brpc %get-block-count ~]
    ==
  [~[(req-card ract)] state]
  ++  req-card
    |=  ract=action:rpc
    =|  out=outbound-config:iris
    =/  req=request:http
      (gen-request host-info ract)
    [%pass /[-.act]/[-.ract]/[(scot %da now.bowl)] %arvo %i %request req out]
  --
::  wire structure
::  /action-tas/rpc-action-tas/timestamp
::
::  TODO use the 2 below to handle responses
::  ~&  >  (parse-response:btc-rpc:blib rpc-resp)
::  ~&  >>   (to-response (rpc-response [%erpc (parse-response:electrum-rpc:elib rpc-resp)]))
++  handle-rpc-response
  |=  [=wire response=client-response:iris]
  ^-  (quip card _state)
  ?.  ?=(%finished -.response)  `state
  =*  status  status-code.response-header.response
  ::  handle error types, in order:
  ::    - connection errors
  ::    - RPC errors
  ::
  =^  conn-err  state
    (connection-error status)
  ?^  conn-err
    ~&  >>>  conn-err
    [~[(send-update [%| u.conn-err])] state]
  =/  rpc-resp=response:rpc:jstd
    (get-rpc-response response)
  ?.  ?=([%result *] rpc-resp)
    [~[(send-update [%| [%rpc-error ~]])] state]
  ::  no error, so handle returned RPC data
  ::
  ?+  wire  ~|("Unexpected HTTP response" !!)
      [%watch-address %erpc *]
    ::  use the %erpc parser here
    ~&  >>  +<.wire   ::  %brpc/%erpc 
    ~&  >  rpc-resp
    `state
      [%ping %brpc *]
    `state(connected.host-info %.y)
  ==
::
++  connection-error
  |=  status=@ud
  ^-  [(unit error) _state]
  ?+  status  [`[%http-error status] state]
      %200
    [~ state]
      %400
    [`[%bad-request status] state]
      %401
    [`[%no-auth status] state(connected.host-info %.n)]
      %502
    [`[%not-connected status] state(connected.host-info %.n)]
      %504
    [`[%not-connected status] state(connected.host-info %.n)]
  ==
::
++  send-update
  |=  =update  ^-  card
  [%give %fact [/clients]~ %btc-provider-update !>(update)]
::
++  is-whitelisted
  |=  user=ship  ^-  ?
  ?|  (~(has in whitelist) user)
      =(our.bowl user)
  ==
++  is-client
  |=  user=ship  ^-  ?
  (~(has in clients.host-info) user)
::
++  httr-to-rpc-response
  |=  hit=httr:eyre
  ^-  response:rpc:jstd
  ~|  hit
  =/  jon=json  (need (de-json:html q:(need r.hit)))
  ?.  =(%2 (div p.hit 100))
    (parse-rpc-error jon)
  =,  dejs-soft:format
  ^-  response:rpc:jstd
  =;  dere
    =+  res=((ar dere) jon)
    ?~  res  (need (dere jon))
    [%batch u.res]
  |=  jon=json
  ^-  (unit response:rpc:jstd)
  =/  res=[id=(unit @t) res=(unit json) err=(unit json)]
    %.  jon
    =,  dejs:format
    =-  (ou -)
    :~  ['id' (uf ~ (mu so))]
        ['result' (uf ~ (mu same))]
        ['error' (uf ~ (mu same))]
    ==
  ?:  ?=([^ * ~] res)
    `[%result [u.id.res ?~(res.res ~ u.res.res)]]
  ~|  jon
  `(parse-rpc-error jon)
::
++  get-rpc-response
  |=  response=client-response:iris
  ^-  response:rpc:jstd
  ?>  ?=(%finished -.response)
  %-  httr-to-rpc-response
    %+  to-httr:iris
      response-header.response
    full-file.response
::
++  parse-rpc-error
  |=  =json
  ^-  response:rpc:jstd
  :-  %error
  ?~  json  ['' '' '']
  %.  json
  =,  dejs:format
  =-  (ou -)
  :~  =-  ['id' (uf '' (cu - (mu so)))]
      |*(a=(unit) ?~(a '' u.a))
      :-  'error'
      =-  (uf ['' ''] -)
      =-  (cu |*(a=(unit) ?~(a ['' ''] u.a)) (mu (ou -)))
      :~  ['code' (uf '' no)]
          ['message' (uf '' so)]
  ==  ==
--

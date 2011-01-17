elementclass GenericRouting4Port {
    // input: a packet to route
    // output[0]: forward to port 0~3 (painted)
    // output[1]: need to update "last" pointer
    // output[2]: no match

    input -> rt :: XIAXIDRouteTable;
    rt[0] -> Paint(0) -> [0]output;
    rt[1] -> Paint(1) -> [0]output;
    rt[2] -> Paint(2) -> [0]output;
    rt[3] -> Paint(3) -> [0]output;
    rt[4] -> [1]output;
    rt[5] -> [2]output;
};

elementclass GenericPostRouteProc {
    input -> XIADecHLIM -> output;
};

elementclass XIAPacketRoute {
    $local_addr |

    // $local_addr: the full address of the node (only used for debugging)

    // input: a packet to process
    // output[0]: forward (painted)
    // output[1]: arrived at destination node
    // output[2]: could not route at all (tried all paths)

    check_dest :: XIACheckDest();
    consider_first_path :: XIASelectPath(first);
    consider_next_path :: XIASelectPath(next);
    c :: XIAXIDTypeClassifier(next AD, next HID, next SID, next CID, -);

    //input -> Print("packet received by $local_addr") -> check_dest;
    input -> check_dest;

    check_dest[0] -> [1]output; // arrived at the final destination
    check_dest[1] -> consider_first_path;

    consider_first_path[0] -> c;
    consider_first_path[1] -> [2]output;
    consider_next_path[0] -> c;
    consider_next_path[1] -> [2]output;

    //  Next destination is AD
    c[0] -> rt_AD :: GenericRouting4Port;
    rt_AD[0] -> GenericPostRouteProc -> [0]output;
    rt_AD[1] -> XIANextHop -> check_dest;
    rt_AD[2] -> consider_next_path;

    //  Next destination is HID
    c[1] -> rt_HID :: GenericRouting4Port;
    rt_HID[0] -> GenericPostRouteProc -> [0]output;
    rt_HID[1] -> XIANextHop -> check_dest;
    rt_HID[2] -> consider_next_path;

    //  Next destination is SID
    c[2] -> rt_SID :: GenericRouting4Port;
    rt_SID[0] -> GenericPostRouteProc -> [0]output;
    rt_SID[1] -> XIANextHop -> check_dest;
    rt_SID[2] -> consider_next_path;


    // change this if you want to do CID post route processing for any reason
    CIDPostRouteProc :: Null;

    //  Next destination is CID
    c[3] -> rt_CID :: GenericRouting4Port;
    rt_CID[0] -> GenericPostRouteProc -> CIDPostRouteProc -> [0]output;
    rt_CID[1] -> XIANextHop -> check_dest;
    rt_CID[2] -> consider_next_path;

    c[4] -> [2]output;
};

elementclass RouteEngine {
    $local_addr |

    // $local_addr: the full address of the node (only used for debugging)

    // input[0]: a packet arrived at the node from outside (i.e. routing with caching)
    // input[1]: a packet to send from a node (i.e. routing without caching)
    // output[0]: forward (painted)
    // output[1]: arrived at destination node; go to RPC
    // output[2]: arrived at destination node; go to cache

    srcTypeClassifier :: XIAXIDTypeClassifier(src CID, -);
    proc :: XIAPacketRoute($local_addr);
    dstTypeClassifier :: XIAXIDTypeClassifier(dst CID, -);

    input[0] -> srcTypeClassifier;
    input[1] -> proc;

    srcTypeClassifier[0] -> cidFork :: Tee(2) -> [2]output;  // To cache (for content caching)
    cidFork[1] -> proc;                 // Main routing process

    srcTypeClassifier[1] -> proc;       // Main routing process

    proc[0] -> [0]output;               // Forward to other interface

    proc[1] -> dstTypeClassifier;
    dstTypeClassifier[1] -> [1]output;  // To RPC

    dstTypeClassifier[0] -> [2]output;  // To cache (for serving content request)

    proc[2] -> Discard;  // No route drop (future TODO: return an error packet)
};

// 1-port host node
elementclass Host {
    $local_addr, $local_hid, $rpc_port |

    // $local_addr: the full address of the node
    // $local_hid:  the HID of the node
    // $rpc_port:   the TCP port number to use for RPC

    // input: a packet arrived at the node
    // output: forward to interface 0

    n :: RouteEngine($local_addr);
    sock :: Socket(TCP, 0.0.0.0, $rpc_port, CLIENT false);
    rpc :: XIARPC($local_addr);
    cache :: XIARouterCache($local_addr, n/proc/rt_CID/rt);

    Script(write n/proc/rt_AD/rt.add - 0);      // default route for AD
    Script(write n/proc/rt_HID/rt.add - 0);     // default route for HID
    Script(write n/proc/rt_HID/rt.add $local_hid 4);  // self HID as destination
    Script(write n/proc/rt_SID/rt.add - 5);     // no default route for SID; consider other path
    Script(write n/proc/rt_CID/rt.add - 5);     // no default route for CID; consider other path

    input[0] -> n;

    sock -> [0]rpc[0] -> sock;
    n[1] -> [1]rpc[1] -> [0]n;
    n[2] -> [0]cache[0] -> [1]n;
    rpc[2] -> [1]cache[1] -> [2]rpc;

    n -> Queue(200) -> [0]output;
};

// 2-port router node
elementclass Router {
    $local_addr, $local_ad, $local_hid |

    // $local_addr: the full address of the node
    // $local_ad:   the AD of the node and the local network
    // $local_hid:  the HID of the node (used for "bound" content source)

    // input[0], input[1]: a packet arrived at the node
    // output[0]: forward to interface 0 (for hosts in local ad)
    // output[1]: forward to interface 1 (for other ads)

    n :: RouteEngine($local_addr);
    cache :: XIARouterCache($local_addr, n/proc/rt_CID/rt);

    Script(write n/proc/rt_AD/rt.add - 1);      // default route for AD
    Script(write n/proc/rt_AD/rt.add $local_ad 4);    // self AD as destination
    Script(write n/proc/rt_HID/rt.add - 0);     // forwarding for local HID
    Script(write n/proc/rt_HID/rt.add $local_hid 4);  // self HID as destination
    Script(write n/proc/rt_SID/rt.add - 5);     // no default route for SID; consider other path
    Script(write n/proc/rt_CID/rt.add - 5);     // no default route for CID; consider other path

    input[0] -> [0]n;
    input[1] -> [0]n;

    n[0] -> sw :: PaintSwitch
    n[1] -> Discard;
    n[2] -> [0]cache[0] -> [1]n;
    Idle -> [1]cache[1] -> Discard;

    sw[0] -> Queue(200) -> [0]output;
    sw[1] -> Queue(200) -> [1]output;
};

// 4-port router node; AD & HID tables need to be set manually using Script()
elementclass Router4Port {
    $local_addr |

    // $local_addr: the full address of the node

    // input[0], input[1], input[2], input[3]: a packet arrived at the node
    // output[0]: forward to interface 0
    // output[1]: forward to interface 1
    // output[2]: forward to interface 2
    // output[3]: forward to interface 3

    n :: RouteEngine($local_addr);
    cache :: XIARouterCache($local_addr, n/proc/rt_CID/rt);

    input[0] -> [0]n;
    input[1] -> [0]n;
    input[2] -> [0]n;
    input[3] -> [0]n;

    n[0] -> sw :: PaintSwitch
    n[1] -> Discard;
    n[2] -> [0]cache[0] -> [1]n;
    Idle -> [1]cache[1] -> Discard;

    sw[0] -> Queue(200) -> [0]output;
    sw[1] -> Queue(200) -> [1]output;
    sw[2] -> Queue(200) -> [2]output;
    sw[3] -> Queue(200) -> [3]output;
};

// IP router node (caution: simplified version for forwarding experiments)
elementclass IPRouter4Port {
    $local_addr |

    // $local_addr: the full address of the node
    // $local_net:  the local network (e.g. 192.168.0.0/24)

    // input[0], input[1], input[2], input[3]: a packet arrived at the node
    // output[0]: forward to interface 0
    // output[1]: forward to interface 1
    // output[2]: forward to interface 2
    // output[3]: forward to interface 3

    rt :: RangeIPLookup;   // fastest IP lookup elem in Click
    dt :: DecIPTTL;
    fr :: IPFragmenter(1500);

    input[0] -> rt;
    input[1] -> rt;
    input[2] -> rt;
    input[3] -> rt;

    rt[0] -> Paint(0) -> dt;
    rt[1] -> Paint(1) -> dt;
    rt[2] -> Paint(2) -> dt;
    rt[3] -> Paint(3) -> dt;

    dt -> fr -> sw :: PaintSwitch;

    dt[1] -> Print("time exceeded") -> Discard; // ICMPError($local_addr, timeexceeded) -> sw;
    fr[1] -> Print("need fragmentation") -> Discard; // ICMPError($local_addr, unreachable, needfrag) -> sw;

    sw[0] -> Queue(200) -> [0]output;
    sw[1] -> Queue(200) -> [1]output;
    sw[2] -> Queue(200) -> [2]output;
    sw[3] -> Queue(200) -> [3]output;
};


define($COUNT 20000000);

XIAXIDInfo(
    AD0 AD:1000000000000000000000000000000000000009,
    AD1 AD:2000000000000000000000000000000000000001,
    AD2 AD:3000000000000000000000000000000000000002,
    AD3 AD:3044444444444444444400000000000000000002,
);



host0 :: Router4Port(RE AD0);

Script(write host0/n/proc/rt_AD/rt.add - 5);
Script(write host0/n/proc/rt_HID/rt.add - 5);
Script(write host0/n/proc/rt_SID/rt.add - 5);
Script(write host0/n/proc/rt_CID/rt.add - 5);

Script(write host0/n/proc/rt_AD/rt.add AD0 4);
Script(write host0/n/proc/rt_AD/rt.add AD1 0);


gen :: InfiniteSource(LENGTH 100, ACTIVE false, HEADROOM 256)
-> Script(TYPE PACKET, write gen.active false)       // stop source after exactly 1 packet
-> XIAEncap(DST RE AD0 AD1, SRC RE AD0)
-> Clone($COUNT)
-> Unqueue
-> host0 
-> Unqueue
-> AggregateCounter(COUNT_STOP $COUNT)
-> Discard;

Idle -> [1]host0;
Idle -> [2]host0;
Idle -> [3]host0;
host0[1] -> Discard;
host0[2] -> Discard;
host0[3] -> Discard;

Script(write gen.active true);


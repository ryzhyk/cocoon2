-- Packet type must be the OpenFlow packet
-- refineRelsUsedInRoles only contain fields of OF-compatible types
-- (i.e, no strings or int's)
-- Switch type must contain OpenFlow channel info: (protocol/host/port, bridge name)
-- Packet type matches the OpenFlow packet type
-- Roles should not write to TCP flags
-- Spec should not explicitly refer to constructors whose tag is not defined in OVSConst.hs
-- Spec should not refer to packet fields not defined in OVSConst
-- (ip.header length, total length, identification, flags)

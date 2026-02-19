local NFS = "sylfn-nfs"
peripheral.find("modem", rednet.open)
local server = rednet.lookup(NFS, "fileserver")
assert(server ~= nil, "no nfs server")
rednet.send(server, "driver", NFS)
local _, driver, _ = rednet.receive(NFS)
load(driver, "=nfs-driver", nil, _ENV)()

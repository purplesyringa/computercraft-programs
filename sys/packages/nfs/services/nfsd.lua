return function(path)
    return {
        description = "Hosts NFS server",
        type = "process",
        command = { "nfsd", path },
    }
end

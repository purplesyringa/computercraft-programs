return {
    description = "Hosts NFS server",
    requires = { "pub" },
    type = "process",
    command = { "nfsd", "pub" },
}

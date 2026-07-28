return {
    description = "Hosts netboot server",
    type = "process",
    requires = { "nfsd@pub" },
    command = { "netbootd" },
}

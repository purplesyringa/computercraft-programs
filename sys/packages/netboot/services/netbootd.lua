return {
    description = "Hosts netboot server",
    type = "process",
    requires = { "nfsd" },
    command = { "netbootd", "sys" },
}

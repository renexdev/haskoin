Haskoin
=======
Haskell implementation of the Bitcoin reference specification

This code is being actively developed and is not stable yet

Current project status:

    - Most of the network protocol messages have been defined
    - Most of the initial blockchain download is implemented
    - Blocks are indexed in leveldb and memory only. Full blocks are not saved yet
    - Other network protocol algorithms have not been defined yet
    - No transaction validation yet
    - No wallet. This is only a server implementation for now
    - No peer management yet. The codebase is still single threaded for now

Conduit is used to process the network IO stream
Memory is managed in the BitcoinMem monad, which runs on top of the STM monad
LevelDB is managed in the BitcoinDB monad, which uses leveldb-haskell library

A lot of experimentation with the codebase is still ongoing. Don't expect the
monad stacks or program structure to be fixed just yet.


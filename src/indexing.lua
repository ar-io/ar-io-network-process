-- dummy indexing protocol implementation


-- message body schema for credit notices that funding the pool
-- credit notice to transfer stake with blind bids using nonce + bid and some hash implementation
-- implmenting partition per pool using Spawn.receive() based on the bids received
-- creating the index pool, spawning the necessary parittions as blocks come in (e.g. every 10000 blocks, new parittion is spawned by the pool process for that block range)
-- indexers initiate the spawning of a new paritition by sending a message to the pool with the partition size and the block range for the new partition (e.g what are the inputs provided by the index number - e.g. the partition number)
-- 

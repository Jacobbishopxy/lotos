-- file: LBW.hs
-- author: Jacob Xie
-- date: 2025/04/06 20:21:31 Sunday
-- brief:
--
-- 1. Acceptor (Dealer) asynchronously receives tasks from the frontend socket.
-- 2. Sender (Pair -> Dealer) cross thread sends tasks to the backend socket.
-- 3. Publisher (Pair -> Pub) cross thread sends logging messages to the logging socket.

module Lotos.Zmq.LBW
  (
  )
where

import Lotos.Zmq.Adt
import Lotos.Zmq.Config

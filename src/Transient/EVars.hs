{-# LANGUAGE DeriveDataTypeable #-}
module Transient.EVars where

import Transient.Base
import Transient.Internals(onNothing, EventF)
import qualified Data.Map as M
import Data.Typeable

import Control.Concurrent
import Control.Applicative
import Control.Concurrent.STM
import Control.Monad.State
import Data.List(nub)

--newtype EVars= EVars  (IORef (M.Map Int [EventF]))  deriving Typeable

data EVar a= EVar Int  (TChan (StreamData a)) deriving  Typeable


-- | creates an EVar.
--
-- Evars are event vars. `writeEVar` trigger the execution of all the continuations associated to the  `readEVar` of this variable
-- (the code that is after them).
--
-- It is like the publish-subscribe pattern but without inversion of control, since a readEVar can be inserted at any place in the
-- Transient flow.
--
-- EVars are created upstream and can be used to communicate two sub-threads of the monad. Following the Transient philosophy they
-- do not block his own thread if used with alternative operators, unlike the IORefs and TVars. And unlike STM vars, that are composable,
-- they wait for their respective events, while TVars execute the whole expression when any variable is modified.
--
-- The execution continues after the writeEVar when all subscribers have been executed.
--
-- Now the continuations are executed in parallel.
--
-- see https://www.fpcomplete.com/user/agocorona/publish-subscribe-variables-transient-effects-v
--

newEVar ::  TransientIO (EVar a)
newEVar  = Transient $ do
   id <- genId
   ref <-liftIO  newTChanIO
   return . Just $ EVar id  ref

-- | delete al the subscriptions for an evar.
delEVar :: EVar a -> TransIO ()
delEVar (EVar id  ref1)= liftIO $ atomically $ writeTChan  ref1 SDone

-- | read the EVar. It only succeed when the EVar is being updated
-- The continuation gets registered to be executed whenever the variable is updated.
-- if readEVar is in any kind of loop, since each continuation is different, this will register
-- again the continuation. The effect is that the continuation will be executed multiple times
-- To avoid multiple registrations, use `unsubscribe`
readEVar :: EVar a -> TransIO a
readEVar (EVar id  ref1)= do
     r <- parallel $ atomically $ readTChan ref1     -- !> "READEVAR"
     case r of
        SDone -> empty
        SMore x -> return x
        SLast x -> return x
        SError e -> error $ show e

-- |  update the EVar and execute all readEVar blocks with "last in-first out" priority
writeEVar (EVar id  ref1) x= liftIO $ atomically $ writeTChan  ref1 $ SMore x




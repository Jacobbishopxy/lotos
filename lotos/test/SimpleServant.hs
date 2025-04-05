{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeOperators #-}

-- file: SimpleServant.hs
-- author: Jacob Xie
-- date: 2025/04/05 21:20:45 Saturday
-- brief:

module Main where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)
import Network.Wai.Handler.Warp (run)
import Servant

-- Our data type for the API
data User = User
  { userId :: Int,
    userName :: Text,
    userEmail :: Text
  }
  deriving (Generic, Show)

-- Automatically derive JSON serialization/deserialization
instance ToJSON User

instance FromJSON User

-- Mock database
type UserDB = [User]

initialDB :: UserDB
initialDB =
  [ User 1 "Jacob" "jacob@example.com",
    User 2 "Mia" "mia@example.com"
  ]

-- API type definition
type UserAPI =
  "users" :> Get '[JSON] [User] -- GET /users
    :<|> "users" :> Capture "id" Int :> Get '[JSON] User -- GET /users/:id
    :<|> "users" :> ReqBody '[JSON] User :> Post '[JSON] User -- POST /users
    :<|> "users" :> Capture "id" Int :> ReqBody '[JSON] User :> Put '[JSON] User -- PUT /users/:id
    :<|> "users" :> Capture "id" Int :> Delete '[JSON] () -- DELETE /users/:id

-- Server implementation
server :: UserDB -> Server UserAPI
server db =
  getUsers
    :<|> getUserById
    :<|> createUser
    :<|> updateUser
    :<|> deleteUser
  where
    -- GET /users - list all users
    getUsers :: Handler [User]
    getUsers = return db

    -- GET /users/:id - get user by ID
    getUserById :: Int -> Handler User
    getUserById i = case filter (\u -> userId u == i) db of
      [] -> throwError err404
      (u : _) -> return u

    -- POST /users - create new user
    createUser :: User -> Handler User
    createUser user = return user {userId = newId}
      where
        newId = if null db then 1 else maximum (map userId db) + 1

    -- PUT /users/:id - update existing user
    updateUser :: Int -> User -> Handler User
    updateUser i updatedUser = do
      if any (\u -> userId u == i) db
        then return updatedUser {userId = i}
        else throwError err404

    -- DELETE /users/:id - delete user
    deleteUser :: Int -> Handler ()
    deleteUser _ = return () -- In a real app, we'd actually remove from DB

-- Convert our API type to a WAI application
app :: UserDB -> Application
app db = serve (Proxy :: Proxy UserAPI) (server db)

-- Run the server
main :: IO ()
main = do
  putStrLn "Starting server on port 8080"
  run 8080 (app initialDB)

{-# LANGUAGE TemplateHaskell #-}

-- file: Adt.hs
-- author: Jacob Xie
-- date: 2024/04/08 08:55:23 Monday
-- brief:

module CronSearch.Adt
  ( module CronSearch.Adt,
  )
where

import Brick.Focus qualified as F
import Brick.Forms (Form)
import Brick.Widgets.List (List)
import Data.Text qualified as T
import Data.Vector qualified as Vec
import Lens.Micro.TH (makeLenses)
import Lotos.Airflow.Cron (Activate, Conj, CronSchema)

-- Source Name
data SourceName
  = SearchRegion SearchRegion
  | ResultHeaderRegion
  | ResultRegion
  | DetailRegion
  deriving (Eq, Ord, Show)

-- Search Region: brick.form
data SearchRegion
  = StringField
  | SelectSleeperField
  | SelectInputField
  | SelectCmdField
  | SelectOutputField
  | SelectServerField
  | SelectUserField
  | ConjAndField
  | ConjOrField
  | ActAllField
  | ActTrueField
  | ActFalseField
  | CaseSensitiveField
  | InvisibleField
  deriving (Eq, Ord, Show)

data Search = Search
  { _searchString :: T.Text,
    -- columns to search
    _selectSleeperCol :: Bool,
    _selectInputCol :: Bool,
    _selectCmdCol :: Bool,
    _selectOutputCol :: Bool,
    _selectServerCol :: Bool,
    _selectUserCol :: Bool,
    -- conjunction
    _conjunction :: Conj,
    -- filter activate
    _selectActivate :: Activate,
    -- ignore case
    _caseSensitive :: Bool,
    -- hidden widget, used when switched out from SearchRegion
    _invisibleFocus :: Bool
  }

makeLenses ''Search

data AppState = AppState
  { _focusRing :: F.FocusRing SourceName,
    -- search form
    _searchForm :: Form Search () SourceName,
    -- all crons
    _allCrons :: Vec.Vector CronSchema,
    -- searched result
    _searchedResult :: Vec.Vector CronSchema,
    _searchedResultList :: List SourceName CronSchema
  }

makeLenses ''AppState

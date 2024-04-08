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
import Lens.Micro.TH (makeLenses)
import Lotos.Airflow.Cron (Conj, CronSchema)

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
  | ConjAndField
  | ConjOrField
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
    -- conjunction
    _conjunction :: Conj,
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
    _allCrons :: [CronSchema],
    -- searched result
    _searchedResult :: [CronSchema],
    _searchedResultList :: List SourceName CronSchema,
    -- searched result
    _selectedResult :: Int
  }

makeLenses ''AppState

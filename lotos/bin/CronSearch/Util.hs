-- file: Util.hs
-- author: Jacob Xie
-- date: 2024/04/08 09:41:04 Monday
-- brief:

module CronSearch.Util
  ( module CronSearch.Util,
  )
where

import Brick
import Brick.Focus qualified as F
import Brick.Forms
import Brick.Widgets.List
import Brick.Widgets.Table (ColumnAlignment (AlignLeft))
import CronSearch.Adt
import Data.List (elemIndex)
import Data.Text qualified as T
import Lens.Micro ((^.))
import Lotos.Airflow

----------------------------------------------------------------------------------------------------
-- Const
----------------------------------------------------------------------------------------------------

-- name & cell width
resultBoxColumnsSetting :: [(String, Int)]
resultBoxColumnsSetting =
  [ ("idx", 5),
    ("dag", 20),
    ("name", 20),
    ("sleeper", 10),
    ("activate", 5)
  ]

resultBoxColumns :: [String]
resultBoxColumns = fst <$> resultBoxColumnsSetting

resultBoxColumnsWidth :: [Int]
resultBoxColumnsWidth = snd <$> resultBoxColumnsSetting

resultBoxColumnsAlignments :: [ColumnAlignment]
resultBoxColumnsAlignments = replicate (length resultBoxColumns) AlignLeft

infoBoxColumns :: [String]
infoBoxColumns =
  [ "idx",
    "dag",
    "name",
    "sleeper",
    "input",
    "cmd",
    "output",
    "server",
    "user",
    "activate",
    "fPath"
  ]

invisibleFormFieldAttr :: AttrName
invisibleFormFieldAttr = focusedFormInputAttr <> attrName "invisibleFormField"

resultHeaderListAttr :: AttrName
resultHeaderListAttr = listAttr <> listSelectedAttr <> attrName "resultHeaderList"

resultSelectedListAttr :: AttrName
resultSelectedListAttr = listSelectedAttr <> attrName "resultSelectedList"

resultUnselectedListAttr :: AttrName
resultUnselectedListAttr = listAttr <> listSelectedAttr <> attrName "resultUnselectedList"

formFocusRingList :: [SearchRegion]
formFocusRingList =
  [ StringField,
    SelectSleeperField,
    SelectInputField,
    SelectCmdField,
    SelectOutputField,
    SelectServerField,
    SelectUserField,
    ConjAndField,
    ConjOrField,
    ActAllField,
    ActTrueField,
    ActFalseField,
    CaseSensitiveField
  ]

focusRingListLength :: Int
focusRingListLength = length formFocusRingList

focusRingList :: [SourceName]
focusRingList =
  [ SearchRegion StringField,
    SearchRegion SelectSleeperField,
    SearchRegion SelectInputField,
    SearchRegion SelectCmdField,
    SearchRegion SelectOutputField,
    SearchRegion SelectServerField,
    SearchRegion SelectUserField,
    SearchRegion ConjAndField,
    SearchRegion ConjOrField,
    SearchRegion ActAllField,
    SearchRegion ActTrueField,
    SearchRegion ActFalseField,
    SearchRegion CaseSensitiveField,
    ResultRegion
  ]

----------------------------------------------------------------------------------------------------

-- key up
formFocusRingLoop :: SearchRegion -> SearchRegion
formFocusRingLoop f = case f `elemIndex` formFocusRingList of
  Just 0 -> CaseSensitiveField
  Just i -> formFocusRingList !! (i - 1)
  _ -> error "formFocusRingLoop"

-- key down
formFocusRingLoop' :: SearchRegion -> SearchRegion
formFocusRingLoop' f = case f `elemIndex` formFocusRingList of
  Just i | i == focusRingListLength - 1 -> StringField
  Just i -> formFocusRingList !! (i + 1)
  _ -> error "formFocusRingLoop'"

-- TODO: check this!

-- from Search to SearchParam
genSearchParam :: Search -> SearchParam
genSearchParam s =
  let flt =
        [ s ^. selectSleeperCol,
          s ^. selectInputCol,
          s ^. selectCmdCol,
          s ^. selectOutputCol,
          s ^. selectServerCol,
          s ^. selectUserCol
        ]
      cols =
        [ "sleeper",
          "input",
          "cmd",
          "output",
          "server",
          "user"
        ]
      sf = [c | (c, f) <- zip cols flt, f]
   in SearchParam
        sf
        (s ^. conjunction)
        (T.unpack $ s ^. searchString)
        (s ^. selectActivate)
        (s ^. caseSensitive)

appCursor :: AppState -> [CursorLocation SourceName] -> Maybe (CursorLocation SourceName)
appCursor = F.focusRingCursor (^. focusRing)

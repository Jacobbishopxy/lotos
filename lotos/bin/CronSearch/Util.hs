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
import CronSearch.Adt
import Data.List (elemIndex)
import Data.Text qualified as T
import Lens.Micro ((^.))
import Lotos.Airflow.Cron

----------------------------------------------------------------------------------------------------
-- Const
----------------------------------------------------------------------------------------------------

resultBoxColumns :: [String]
resultBoxColumns =
  [ "idx",
    "dag",
    "name",
    "sleeper",
    "input",
    "cmd",
    "output",
    "activate",
    "fPath"
  ]

-- fixed length
columnWidths :: [Int]
columnWidths =
  [ 5,
    15,
    15,
    10,
    40,
    40,
    40,
    5,
    40
  ]

invisibleFormFieldAttr :: AttrName
invisibleFormFieldAttr = focusedFormInputAttr <> attrName "invisibleFormField"

resultHeaderListAttr :: AttrName
resultHeaderListAttr = listAttr <> listSelectedAttr <> attrName "resultHeaderList"

resultSelectedListAttr :: AttrName
resultSelectedListAttr = listSelectedAttr <> attrName "resultSelectedList"

resultUnselectedListAttr :: AttrName
resultUnselectedListAttr = listAttr <> listSelectedAttr <> attrName "resultUnselectedList"

detailSelectedListAttr :: AttrName
detailSelectedListAttr = listSelectedAttr <> attrName "detailSelectedList"

formFocusRingList :: [SearchRegion]
formFocusRingList =
  [ StringField,
    SelectSleeperField,
    SelectInputField,
    SelectCmdField,
    SelectOutputField,
    ConjAndField,
    ConjOrField,
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
    SearchRegion ConjAndField,
    SearchRegion ConjOrField,
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

-- from Search to SearchParam
genSearchParam :: Search -> SearchParam
genSearchParam s =
  let flt = [s ^. selectSleeperCol, s ^. selectInputCol, s ^. selectCmdCol, s ^. selectOutputCol]
      cols = ["sleeper", "input", "cmd", "output"]
      sf = [c | (c, f) <- zip cols flt, f]
   in SearchParam sf (s ^. conjunction) (T.unpack $ s ^. searchString)

appCursor :: AppState -> [CursorLocation SourceName] -> Maybe (CursorLocation SourceName)
appCursor = F.focusRingCursor (^. focusRing)

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
import Lotos.Airflow.Cron

----------------------------------------------------------------------------------------------------
-- Const
----------------------------------------------------------------------------------------------------

-- name & cell width
resultBoxColumnsSetting :: [(String, Int)]
resultBoxColumnsSetting =
  [ ("idx", 5),
    ("dag", 15),
    ("name", 15),
    ("sleeper", 10),
    ("input", 40),
    ("cmd", 40),
    ("output", 40),
    ("activate", 5),
    ("fPath", 40)
  ]

resultBoxColumns :: [String]
resultBoxColumns = fst <$> resultBoxColumnsSetting

resultBoxColumnsWidth :: [Int]
resultBoxColumnsWidth = snd <$> resultBoxColumnsSetting

resultBoxColumnsAlignments :: [ColumnAlignment]
resultBoxColumnsAlignments = replicate (length resultBoxColumns) AlignLeft

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

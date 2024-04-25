{-# LANGUAGE OverloadedStrings #-}

-- file: CronSearch.hs
-- author: Jacob Xie
-- date: 2024/04/08 08:41:06 Monday
-- brief:

module Main where

import Brick
import Brick.Focus qualified as F
import Brick.Forms
import Brick.Widgets.Border
import Brick.Widgets.Center
import Brick.Widgets.Edit
import Brick.Widgets.List
import Brick.Widgets.Table
import Control.Monad (void)
import CronSearch.Adt
import CronSearch.Util
import Data.List (intercalate)
import Data.Text qualified as T
import Data.Vector qualified as Vec
import Graphics.Vty qualified as V
import Graphics.Vty.CrossPlatform (mkVty)
import Lens.Micro
import Lens.Micro.Mtl
import Lotos.Airflow.Conf
import Lotos.Airflow.Cron
import System.Environment (getArgs)

----------------------------------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------------------------------

drawUi :: AppState -> [Widget SourceName]
drawUi st = [ui]
  where
    ui =
      vBox
        [ vLimit 14 $
            borderWithLabel titleSP $
              hLimitPercent 60 (controlBox st) <+> hCenter (vCenter helpBox),
          hBox
            [ hLimitPercent 40 $ borderWithLabel titleMR $ resultBox st,
              borderWithLabel titleDI $ infoBox st <=> fill ' '
            ]
        ]
    titleSP = str "search param"
    titleDI = str "detailed info"
    titleMR = str "matched result"

-- control box
controlBox :: AppState -> Widget SourceName
controlBox st = renderForm (st ^. searchForm)

-- help box
helpBox :: Widget SourceName
helpBox =
  str $
    "help:\n"
      <> "Arrow:   move up/down\n"
      <> "Space:   select param\n"
      <> "Enter:   search\n"
      <> "Tab:     switch panel\n"
      <> "Esc:     quit"

-- result box
resultBox :: AppState -> Widget SourceName
resultBox st =
  vLimit 1 (renderList listDrawResultHeader False h) <=> r
  where
    -- header
    h = list ResultHeaderRegion (Vec.fromList [resultBoxColumns]) 1
    l = renderList listDrawResult False $ st ^. searchedResultList
    -- if not on focus, disable highlight
    r = case F.focusGetCurrent $ st ^. focusRing of
      -- when focus ring on
      Just ResultRegion -> l
      -- when focus ring off
      _ -> withAttr resultUnselectedListAttr l

-- TODO: fix input/cmd/output
-- info box
infoBox :: AppState -> Widget SourceName
infoBox st =
  maybe emptyWidget ((`g` infoBoxColumns) . snd) s
  where
    -- generate info list
    g :: CronSchema -> [String] -> Widget SourceName
    g cs c =
      strWrap $
        intercalate "\n" [c' <> ": " <> s' | (c', s') <- zip c (getCronStrings cs c)]
    s = listSelectedElement $ st ^. searchedResultList

----------------------------------------------------------------------------------------------------

-- form builder
mkForm :: Search -> Form Search e SourceName
mkForm =
  newForm
    [ labelP "Lookup string" @@= editTextField searchString (SearchRegion StringField) (Just 1),
      label "Select columns" @@= checkboxField selectSleeperCol (SearchRegion SelectSleeperField) "Sleeper",
      label "" @@= checkboxField selectInputCol (SearchRegion SelectInputField) "Input",
      label "" @@= checkboxField selectCmdCol (SearchRegion SelectCmdField) "Cmd",
      labelP "" @@= checkboxField selectOutputCol (SearchRegion SelectOutputField) "Output",
      labelP "Conjunction" @@= radioField conjunction radioG,
      labelP "Case sensitive" @@= checkboxField caseSensitive (SearchRegion CaseSensitiveField) "",
      labelI @@= checkboxField invisibleFocus (SearchRegion InvisibleField) ""
    ]
  where
    label s w = vLimit 1 (hLimit 20 $ str s <+> fill ' ') <+> w
    labelP s w = padBottom (Pad 1) $ label s w
    labelI = withAttr invisibleFormFieldAttr
    radioG = [(AND, SearchRegion ConjAndField, "And"), (OR, SearchRegion ConjOrField, "Or")]

-- result header
listDrawResultHeader :: Bool -> [String] -> Widget SourceName
listDrawResultHeader _ cs =
  withAttr resultHeaderListAttr $
    hBox $
      alignColumns resultBoxColumnsAlignments resultBoxColumnsWidth $
        str <$> cs

-- draw result list item
listDrawResult :: Bool -> CronSchema -> Widget SourceName
listDrawResult _ cs =
  hBox $ alignColumns resultBoxColumnsAlignments resultBoxColumnsWidth $ txt . T.pack <$> c
  where
    c = getCronStrings cs resultBoxColumns

----------------------------------------------------------------------------------------------------
-- Event
----------------------------------------------------------------------------------------------------

appEvent :: BrickEvent SourceName () -> EventM SourceName AppState ()
-- quit
appEvent (VtyEvent (V.EvKey V.KEsc [])) = halt
-- press Tab/BackTab switch to next panel
appEvent (VtyEvent (V.EvKey (V.KChar '\t') [])) = switchRegion
appEvent (VtyEvent (V.EvKey V.KBackTab [])) = switchRegion
-- press Enter to search while in `SearchRegion`
appEvent (VtyEvent (V.EvKey V.KEnter [])) = do
  r <- use focusRing
  case F.focusGetCurrent r of
    Just (SearchRegion _) -> modify commitSearchRequest
    _ -> return ()
-- press arrow Up
appEvent (VtyEvent k@(V.EvKey V.KUp [])) = do
  r <- use focusRing
  case F.focusGetCurrent r of
    -- arrow up/down effects detailed info
    Just ResultRegion ->
      zoom searchedResultList $ handleListEvent k
    -- move to the previous form focus
    Just (SearchRegion f) -> do
      let f' = SearchRegion $ formFocusRingLoop f
      focusRing %= F.focusSetCurrent f'
      modify $ searchForm %~ setFormFocus f'
    _ -> return ()
-- press arrow Down
appEvent (VtyEvent k@(V.EvKey V.KDown [])) = do
  r <- use focusRing
  case F.focusGetCurrent r of
    -- arrow up/down effects detailed info
    Just ResultRegion ->
      zoom searchedResultList $ handleListEvent k
    -- move to the next form focus
    Just (SearchRegion f) -> do
      let f' = SearchRegion $ formFocusRingLoop' f
      focusRing %= F.focusSetCurrent f'
      modify $ searchForm %~ setFormFocus f'
    _ -> return ()
-- other cases
appEvent ev@(VtyEvent ve) = do
  r <- use focusRing
  case F.focusGetCurrent r of
    Just (SearchRegion _) -> zoom searchForm $ handleFormEvent ev
    Just ResultRegion -> zoom searchedResultList $ handleListEvent ve
    _ -> return ()
appEvent _ = return ()

-- switch between SearchRegion and ResultRegion
switchRegion :: EventM SourceName AppState ()
switchRegion = do
  r <- use focusRing
  case F.focusGetCurrent r of
    Just (SearchRegion _) -> do
      focusRing %= F.focusSetCurrent ResultRegion
      modify $ searchForm %~ setFormFocus (SearchRegion InvisibleField)
    Just ResultRegion -> do
      focusRing %= F.focusSetCurrent (SearchRegion StringField)
      modify $ searchForm %~ setFormFocus (SearchRegion StringField)
    _ -> return ()

-- according to the current form states, update filtered result
commitSearchRequest :: AppState -> AppState
commitSearchRequest st =
  let sp = genSearchParam $ formState $ st ^. searchForm
      sr = searchCron sp (st ^. allCrons)
   in st
        & searchedResult .~ sr
        & searchedResultList .~ list ResultRegion sr 1
        & searchForm %~ setFormFocus (SearchRegion InvisibleField) -- set form focus to null
        & focusRing %~ F.focusSetCurrent ResultRegion -- jump to result region

----------------------------------------------------------------------------------------------------
-- Attr
----------------------------------------------------------------------------------------------------

theMap :: AttrMap
theMap =
  attrMap
    V.defAttr
    [ (editAttr, V.white `on` V.black),
      (editFocusedAttr, V.black `on` V.yellow),
      (listAttr, V.white `Brick.on` V.black),
      (listSelectedAttr, V.black `Brick.on` V.yellow),
      (formAttr, V.white `Brick.on` V.black),
      (focusedFormInputAttr, V.black `on` V.yellow),
      -- overwrite
      (invisibleFormFieldAttr, fg V.black),
      (resultHeaderListAttr, V.white `on` V.blue),
      (resultUnselectedListAttr, V.white `on` V.black)
    ]

----------------------------------------------------------------------------------------------------
-- App
----------------------------------------------------------------------------------------------------

app :: App AppState () SourceName
app =
  App
    { appDraw = drawUi,
      appChooseCursor = appCursor,
      appHandleEvent = appEvent,
      appStartEvent = return (),
      appAttrMap = const theMap
    }

defaultSearch :: Search
defaultSearch =
  Search
    { _searchString = "",
      _selectSleeperCol = False,
      _selectInputCol = True,
      _selectCmdCol = True,
      _selectOutputCol = True,
      _conjunction = OR,
      _caseSensitive = False,
      _invisibleFocus = False
    }

initialState :: Vec.Vector CronSchema -> AppState
initialState cs =
  AppState
    { _focusRing = F.focusRing focusRingList,
      _searchForm = mkForm defaultSearch,
      _allCrons = cs,
      _searchedResult = Vec.empty,
      _searchedResultList = list ResultRegion Vec.empty 0
    }

----------------------------------------------------------------------------------------------------
-- Main
----------------------------------------------------------------------------------------------------

main :: IO ()
main = do
  args <- getArgs

  -- read yaml file and load all crons
  let yamlPath = case args of
        (x : _) -> x
        [] -> "./cron.yml"
  s <- readConf yamlPath
  crons <- getAllCrons $ lookupDirs s

  -- build vty
  let vtyBuilder = mkVty V.defaultConfig
  initialVty <- vtyBuilder

  -- Tui
  void $ customMain initialVty vtyBuilder Nothing app (initialState crons)

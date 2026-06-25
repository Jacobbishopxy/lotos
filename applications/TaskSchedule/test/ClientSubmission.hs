{-# LANGUAGE OverloadedStrings #-}

module Main where

import Adt (ClientTask (..), ScheduleHints (..))
import Client (readTaskFromTomlText)
import Control.Monad (when)
import Data.List (isInfixOf)
import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Lotos.Zmq (Task (..))
import System.Exit (exitFailure)
import Test.HUnit

sampleTaskTomlPath :: FilePath
sampleTaskTomlPath = "config/task-demo.toml"

parseSampleTomlText :: Assertion
parseSampleTomlText = do
  tomlText <- TextIO.readFile sampleTaskTomlPath
  case readTaskFromTomlText tomlText of
    Left err -> assertFailure $ "sample task TOML failed to parse: " <> err
    Right task -> do
      taskID task @?= Nothing
      taskContent task @?= "write a TaskSchedule MVP marker file"
      taskTimeout task @?= 5
      let clientTask = taskProp task
          schedule = clientTaskSchedule clientTask
      clientTaskName clientTask @?= "write a TaskSchedule MVP marker file"
      scheduleMaxRuntimeSec schedule @?= Just 5
      scheduleMaxCpuPercent schedule @?= Just 100
      scheduleMaxRssMb schedule @?= Just 128
      length (clientTaskSteps clientTask) @?= 1

invalidTomlReturnsParseError :: Assertion
invalidTomlReturnsParseError =
  case readTaskFromTomlText "schemaVersion = [\n" of
    Left err -> assertBool "parse error text should not be empty" (not $ null err)
    Right task -> assertFailure $ "invalid TOML unexpectedly parsed as " <> show task

emptyStepsToml :: Text.Text
emptyStepsToml =
  Text.unlines
    [ "schemaVersion = \"task-schedule/v2\"",
      "name = \"missing steps\"",
      "labels = []",
      "",
      "[retry]",
      "maxAttempts = 0",
      "intervalSec = 0",
      "",
      "[schedule]",
      "priority = 0",
      "requiredTags = []",
      "preferredTags = []",
      "maxRuntimeSec = 1"
    ]

invalidContractReturnsValidationError :: Assertion
invalidContractReturnsValidationError =
  case readTaskFromTomlText emptyStepsToml of
    Left err -> assertBool "validation error should mention missing steps" ("at least one [[steps]] entry is required" `isInfixOf` err)
    Right task -> assertFailure $ "invalid task contract unexpectedly parsed as " <> show task

invalidCpuLimitToml :: Text.Text
invalidCpuLimitToml =
  Text.unlines
    [ "schemaVersion = \"task-schedule/v2\"",
      "name = \"bad cpu\"",
      "labels = []",
      "",
      "[retry]",
      "maxAttempts = 0",
      "intervalSec = 0",
      "",
      "[schedule]",
      "priority = 0",
      "requiredTags = []",
      "preferredTags = []",
      "maxCpuPercent = 101",
      "maxRssMb = 128",
      "",
      "[[steps]]",
      "name = \"run\"",
      "[steps.run]",
      "type = \"shell\"",
      "command = \"sh\"",
      "args = [\"-c\", \"true\"]",
      "timeoutSec = 1"
    ]

invalidResourceLimitsReturnValidationError :: Assertion
invalidResourceLimitsReturnValidationError =
  case readTaskFromTomlText invalidCpuLimitToml of
    Left err -> assertBool "validation error should mention maxCpuPercent" ("schedule.maxCpuPercent" `isInfixOf` err)
    Right task -> assertFailure $ "invalid resource limit unexpectedly parsed as " <> show task


tests :: Test
tests =
  TestList
    [ TestLabel "parse sample task TOML text" (TestCase parseSampleTomlText),
      TestLabel "invalid TOML returns a parse error" (TestCase invalidTomlReturnsParseError),
      TestLabel "invalid task contract returns a validation error" (TestCase invalidContractReturnsValidationError),
      TestLabel "invalid resource limits return a validation error" (TestCase invalidResourceLimitsReturnValidationError)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure

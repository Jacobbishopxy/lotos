{-# LANGUAGE OverloadedStrings #-}

module Main where

import Client (readTaskFromFile, readTaskFromTomlText)
import ClientBridge
  ( SubmitRequest (..),
    SubmitResponse (..),
    parseSubmitRequestBody,
    submitTaskTomlWith,
  )
import Control.Monad (when)
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Lotos.Zmq (Ack, Task (..), ackFromText)
import System.Exit (exitFailure)
import Test.HUnit

samplePath :: FilePath
samplePath = "config/task-demo.toml"

fixedAck :: Ack
fixedAck =
  case ackFromText "2026-01-01T00:00:00Z" of
    Right ack -> ack
    Left err -> error $ "invalid fixed ACK fixture: " <> show err

assertLeftContains :: Text.Text -> Either String a -> Assertion
assertLeftContains expected result =
  case result of
    Left err -> assertBool ("expected error containing " <> Text.unpack expected <> ", got: " <> err) (expected `Text.isInfixOf` Text.pack err)
    Right _ -> assertFailure "expected Left validation error"

sampleTomlTextParsesLikeFile :: Assertion
sampleTomlTextParsesLikeFile = do
  tomlText <- TextIO.readFile samplePath
  fromFile <- readTaskFromFile samplePath
  fromText <- pure $ readTaskFromTomlText tomlText
  taskFromFile <- either assertFailure pure fromFile
  taskFromText <- either assertFailure pure fromText
  taskID taskFromText @?= taskID taskFromFile
  taskContent taskFromText @?= taskContent taskFromFile
  taskRetry taskFromText @?= taskRetry taskFromFile
  taskRetryInterval taskFromText @?= taskRetryInterval taskFromFile
  taskTimeout taskFromText @?= taskTimeout taskFromFile
  taskProp taskFromText @?= taskProp taskFromFile
  response <- submitTaskTomlWith (\_ -> pure $ Just fixedAck) 5 (SubmitRequest "toml" tomlText)
  response @?= SubmitResponse True "accepted" "accepted/enqueued" (Just "write a TaskSchedule MVP marker file")

missingStepsAreValidationErrors :: Assertion
missingStepsAreValidationErrors = do
  let tomlText =
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
            "priority = 50",
            "requiredTags = []",
            "preferredTags = []"
          ]
  assertLeftContains "at least one [[steps]] entry is required" (readTaskFromTomlText tomlText)

malformedTomlIsValidationError :: Assertion
malformedTomlIsValidationError =
  assertLeftContains "unexpected end of input" (readTaskFromTomlText "schemaVersion =")

parseRejectsUnsupportedFormat :: Assertion
parseRejectsUnsupportedFormat = do
  let body = BL8.pack "{\"format\":\"json\",\"taskToml\":\"name = \\\"x\\\"\"}"
  case parseSubmitRequestBody 65536 body of
    Left response -> do
      responseOk response @?= False
      responseStatus response @?= "unsupported-format"
      assertBool "unsupported format should be explained" ("unsupported format" `Text.isInfixOf` responseMessage response)
    Right _ -> assertFailure "unsupported format should not parse"

parseRejectsBrowserSuppliedConfig :: Assertion
parseRejectsBrowserSuppliedConfig = do
  let body = BL8.pack "{\"format\":\"toml\",\"taskToml\":\"schemaVersion = \\\"task-schedule/v2\\\"\",\"clientId\":\"evil\"}"
  case parseSubmitRequestBody 65536 body of
    Left response -> do
      responseStatus response @?= "validation-error"
      assertBool "extra config fields should be rejected" ("unsupported request field" `Text.isInfixOf` responseMessage response)
    Right _ -> assertFailure "browser-supplied client config should not parse"

parseRejectsOversizeBody :: Assertion
parseRejectsOversizeBody = do
  let body = BL8.pack "{\"format\":\"toml\",\"taskToml\":\"schemaVersion = \\\"task-schedule/v2\\\"\"}"
  case parseSubmitRequestBody 10 body of
    Left response -> do
      responseStatus response @?= "validation-error"
      assertBool "oversize policy should be explicit" ("bridgeMaxRequestBytes" `Text.isInfixOf` responseMessage response)
    Right _ -> assertFailure "oversize body should not parse"

ackTimeoutMapsToStructuredResponse :: Assertion
ackTimeoutMapsToStructuredResponse = do
  tomlText <- TextIO.readFile samplePath
  response <- submitTaskTomlWith (\_ -> pure Nothing) 7 (SubmitRequest "toml" tomlText)
  responseOk response @?= False
  responseStatus response @?= "ack-timeout"
  responseMessage response @?= "no ACK received before reqTimeoutSec (7s)"

invalidTomlDoesNotSubmit :: Assertion
invalidTomlDoesNotSubmit = do
  response <- submitTaskTomlWith (\_ -> assertFailure "submitter should not be called for invalid TOML" >> pure Nothing) 5 (SubmitRequest "toml" "schemaVersion =")
  responseOk response @?= False
  responseStatus response @?= "validation-error"

tests :: Test
tests =
  TestList
    [ TestLabel "sample TOML text parses like file and maps accepted ACK" (TestCase sampleTomlTextParsesLikeFile),
      TestLabel "missing steps are validation errors" (TestCase missingStepsAreValidationErrors),
      TestLabel "malformed TOML is a validation error" (TestCase malformedTomlIsValidationError),
      TestLabel "unsupported format is rejected" (TestCase parseRejectsUnsupportedFormat),
      TestLabel "browser-supplied client config is rejected" (TestCase parseRejectsBrowserSuppliedConfig),
      TestLabel "oversize submit request is rejected" (TestCase parseRejectsOversizeBody),
      TestLabel "ACK timeout maps to structured response" (TestCase ackTimeoutMapsToStructuredResponse),
      TestLabel "invalid TOML does not invoke submitter" (TestCase invalidTomlDoesNotSubmit)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure

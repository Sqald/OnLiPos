// controllers配下の*_controllerファイルをすべて自動検出し、Stimulusアプリケーションに登録する。
// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

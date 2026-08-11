// Stimulusアプリケーションのインスタンスを生成し、他のコントローラファイルから利用できるようexportする。
import { Application } from "@hotwired/stimulus"

const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus   = application

export { application }

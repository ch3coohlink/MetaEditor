import { chromium } from 'playwright'
import path from 'path'
import os from 'os'
import fs from 'fs'

const __dirname = path.dirname(new URL(import.meta.url).pathname).substring(1)
const portFile = path.join(__dirname, '../../.port')

async function run() {
  console.log('--- E2E Stress Test: Click Twice ---')
  
  let port = '8080'
  if (fs.existsSync(portFile)) port = fs.readFileSync(portFile, 'utf8').trim()
  const url = `http://localhost:${port}`

  const browser = await chromium.launch({ headless: true })
  const page = await browser.newPage()

  try {
    await page.goto(url, { waitUntil: 'networkidle' })
    await page.waitForTimeout(1000)

    console.log('Click 1...')
    await page.click('button')
    await page.waitForTimeout(500)
    
    console.log('Click 2...')
    await page.click('button')
    await page.waitForTimeout(500)

    const content = await page.textContent('body')
    console.log(`Final body content includes: ${content.includes('Count: 2') ? 'Count: 2 (FOUND)' : 'Count: 2 (NOT FOUND)'}`)
    
    if (content.includes('Count: 2')) {
      console.log('STRESS TEST SUCCESS: Counter reached 2')
    } else {
      console.log('STRESS TEST FAILURE: Counter value mismatch')
      console.log('Full Body Text:', content)
    }

  } catch (e) { console.error(e) }
  finally { await browser.close() }
}
run()

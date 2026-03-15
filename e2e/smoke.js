/**
 * MetaEditor E2E Smoke Test
 * 
 * Run this to verify the local MoonBit app is working correctly.
 * Usage: $env:NODE_PATH="C:\Users\ch3coohlink\AppData\Roaming\npm\node_modules"; node e2e/meta_smoke.js
 */

const { chromium } = require('playwright')
const path = require('path');

(async () => {
  console.log('--- Start E2E Smoke Test ---')

  const browser = await chromium.launch({ headless: true })
  const page = await browser.newPage()

  // Track if MoonBit link successful
  let isBridgeReady = false
  let isMbtActive = false

  page.on('console', msg => {
    const text = msg.text()
    console.log(`[BROWSER CONSOLE] ${text}`)
    if (text.includes('Bridge (Non-Module) is ready')) isBridgeReady = true
    if (text.includes('MoonBit Logic Active')) isMbtActive = true
  })

  page.on('pageerror', err => {
    console.error(`[BROWSER ERROR] ${err.message}`)
  })

  try {
    const targetUrl = 'http://localhost:8080/MetaEditor/'
    console.log(`Navigating to ${targetUrl}...`)

    await page.goto(targetUrl, { waitUntil: 'networkidle', timeout: 5000 })

    // Wait a bit for async bridge sync
    await page.waitForTimeout(1000)

    const title = await page.title()
    console.log(`Page Title: ${title}`)

    // Verify UI items
    const headerText = await page.innerText('h1')
    console.log(`Headline Found: ${headerText}`)

    const counterValue = await page.innerText('div >> text=/\\d+/')
    console.log(`Initial Counter Value: ${counterValue}`)

    // --- INTERACTION TEST ---
    console.log('\nTesting interaction: Clicking Increment button...')
    await page.click('button:has-text("Increment")')
    
    // Wait for the bridge to sync the update
    await page.waitForTimeout(500)
    
    const newCounterValue = await page.innerText('div >> text=/\\d+/')
    console.log(`New Counter Value: ${newCounterValue}`)

    if (newCounterValue === '1') {
      console.log('SUCCESS: Interaction working. Counter incremented.')
    } else {
      console.error('FAILURE: Interaction failed. Counter did not change.')
    }
    // ------------------------

    // Check Status
    if (isBridgeReady && isMbtActive) {
      console.log('\nSUCCESS: MoonBit Logic is correctly linked and active.')
    } else {
      console.warn('\nWARNING: Some bridge components were not detected.')
    }

    const os = require('os');
    const screenshotPath = path.join(os.tmpdir(), 'metaeditor_smoke_result.png');
    await page.screenshot({ path: screenshotPath });
    console.log(`Screenshot saved to: ${screenshotPath}`);

  } catch (error) {
    console.error(`\nTEST FAILED: ${error.message}`)
  } finally {
    await browser.close()
    console.log('--- End E2E Smoke Test ---')
  }
})()

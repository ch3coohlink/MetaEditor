module.exports = {
  title: 'MetaEditor CSS 引擎路线图',
  language: 'zh-CN',
  size: 'A4',
  theme: undefined,
  entry: 'out/css-roadmap/index.html',
  output: [
    {
      path: 'out/css-roadmap/css-roadmap.pdf',
      format: 'pdf',
    },
  ],
  renderDelay: 15000,
  timeout: 300000,
}

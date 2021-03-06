
Color = require './color'
ColorParser = null
ColorExpression = require './color-expression'
SVGColors = require './svg-colors'
DVIPnames = require './dvipnames'
BlendModes = require './blend-modes'
scopeFromFileName = require './scope-from-file-name'
{split, clamp, clampInt} = require './utils'
{
  int
  float
  percent
  optionalPercent
  intOrPercent
  floatOrPercent
  comma
  notQuote
  hexadecimal
  ps
  pe
  variables
  namePrefixes
} = require './regexes'

module.exports =
class ColorContext
  constructor: (options={}) ->
    {variables, colorVariables, @referenceVariable, @referencePath, @rootPaths, @parser, @colorVars, @vars, @defaultVars, @defaultColorVars, sorted, @registry, @sassScopeSuffix} = options

    variables ?= []
    colorVariables ?= []
    @rootPaths ?= []
    @referencePath ?= @referenceVariable.path if @referenceVariable?

    if @sorted
      @variables = variables
      @colorVariables = colorVariables
    else
      @variables = variables.slice().sort(@sortPaths)
      @colorVariables = colorVariables.slice().sort(@sortPaths)

    unless @vars?
      @vars = {}
      @colorVars = {}
      @defaultVars = {}
      @defaultColorVars = {}

      for v in @variables
        @vars[v.name] = v
        @defaultVars[v.name] = v if v.path.match /\/.pigments$/

      for v in @colorVariables
        @colorVars[v.name] = v
        @defaultColorVars[v.name] = v if v.path.match /\/.pigments$/

    if not @registry.getExpression('pigments:variables')? and @colorVariables.length > 0
      expr = ColorExpression.colorExpressionForColorVariables(@colorVariables)
      @registry.addExpression(expr)

    unless @parser?
      ColorParser = require './color-parser'
      @parser = new ColorParser(@registry, this)

    @usedVariables = []
    @resolvedVariables = []

  sortPaths: (a,b) =>
    if @referencePath?
      return 0 if a.path is b.path
      return 1 if a.path is @referencePath
      return -1 if b.path is @referencePath

      rootReference = @rootPathForPath(@referencePath)
      rootA = @rootPathForPath(a.path)
      rootB = @rootPathForPath(b.path)

      return 0 if rootA is rootB
      return 1 if rootA is rootReference
      return -1 if rootB is rootReference

      0
    else
      0

  rootPathForPath: (path) ->
    return root for root in @rootPaths when path.indexOf("#{root}/") is 0

  clone: ->
    new ColorContext({
      @variables
      @colorVariables
      @referenceVariable
      @parser
      @vars
      @colorVars
      @defaultVars
      @defaultColorVars
      sorted: true
    })

  ##    ##     ##    ###    ########   ######
  ##    ##     ##   ## ##   ##     ## ##    ##
  ##    ##     ##  ##   ##  ##     ## ##
  ##    ##     ## ##     ## ########   ######
  ##     ##   ##  ######### ##   ##         ##
  ##      ## ##   ##     ## ##    ##  ##    ##
  ##       ###    ##     ## ##     ##  ######

  containsVariable: (variableName) -> variableName in @getVariablesNames()

  hasColorVariables: -> @colorVariables.length > 0

  getVariables: -> @variables

  getColorVariables: -> @colorVariables

  getVariablesNames: -> @varNames ?= Object.keys(@vars)

  getVariablesCount: -> @varCount ?= @getVariablesNames().length

  readUsedVariables: ->
    usedVariables = []
    usedVariables.push v for v in @usedVariables when v not in usedVariables
    @usedVariables = []
    @resolvedVariables = []
    usedVariables

  ##    ##     ##    ###    ##       ##     ## ########  ######
  ##    ##     ##   ## ##   ##       ##     ## ##       ##    ##
  ##    ##     ##  ##   ##  ##       ##     ## ##       ##
  ##    ##     ## ##     ## ##       ##     ## ######    ######
  ##     ##   ##  ######### ##       ##     ## ##             ##
  ##      ## ##   ##     ## ##       ##     ## ##       ##    ##
  ##       ###    ##     ## ########  #######  ########  ######

  getValue: (value) ->
    [realValue, lastRealValue] = []
    lookedUpValues = [value]

    while (realValue = @vars[value]?.value) and realValue not in lookedUpValues
      @usedVariables.push(value)
      value = lastRealValue = realValue
      lookedUpValues.push(realValue)

    if realValue in lookedUpValues then undefined else lastRealValue

  readColorExpression: (value) ->
    if @colorVars[value]?
      @usedVariables.push(value)
      @colorVars[value].value
    else
      value

  readColor: (value, keepAllVariables=false) ->
    return if value in @usedVariables and not (value in @resolvedVariables)

    realValue = @readColorExpression(value)

    return if not realValue? or realValue in @usedVariables

    scope = if @colorVars[value]?
      @scopeFromFileName(@colorVars[value].path)
    else
      '*'

    @usedVariables = @usedVariables.filter (v) -> v isnt realValue
    result = @parser.parse(realValue, scope, false)

    if result?
      if result.invalid and @defaultColorVars[realValue]?
        result = @readColor(@defaultColorVars[realValue].value)
        value = realValue

    else if @defaultColorVars[value]?
      @usedVariables.push(value)
      result = @readColor(@defaultColorVars[value].value)

    else
      @usedVariables.push(value) if @vars[value]?

    if result?
      @resolvedVariables.push(value)
      if keepAllVariables or value not in @usedVariables
        result.variables = (result.variables ? []).concat(@readUsedVariables())

    return result

  scopeFromFileName: (path) ->
    scope = scopeFromFileName(path)

    if scope is 'sass' or scope is 'scss'
      scope = [scope, @sassScopeSuffix].join(':')

    scope

  readFloat: (value) ->
    res = parseFloat(value)

    if isNaN(res) and @vars[value]?
      @usedVariables.push value
      res = @readFloat(@vars[value].value)

    if isNaN(res) and @defaultVars[value]?
      @usedVariables.push value
      res = @readFloat(@defaultVars[value].value)

    res

  readInt: (value, base=10) ->
    res = parseInt(value, base)

    if isNaN(res) and @vars[value]?
      @usedVariables.push value
      res = @readInt(@vars[value].value)

    if isNaN(res) and @defaultVars[value]?
      @usedVariables.push value
      res = @readInt(@defaultVars[value].value)

    res

  readPercent: (value) ->
    if not /\d+/.test(value) and @vars[value]?
      @usedVariables.push value
      value = @readPercent(@vars[value].value)

    if not /\d+/.test(value) and @defaultVars[value]?
      @usedVariables.push value
      value = @readPercent(@defaultVars[value].value)

    Math.round(parseFloat(value) * 2.55)

  readIntOrPercent: (value) ->
    if not /\d+/.test(value) and @vars[value]?
      @usedVariables.push value
      value = @readIntOrPercent(@vars[value].value)

    if not /\d+/.test(value) and @defaultVars[value]?
      @usedVariables.push value
      value = @readIntOrPercent(@defaultVars[value].value)

    return NaN unless value?
    return value if typeof value is 'number'

    if value.indexOf('%') isnt -1
      res = Math.round(parseFloat(value) * 2.55)
    else
      res = parseInt(value)

    res

  readFloatOrPercent: (value) ->
    if not /\d+/.test(value) and @vars[value]?
      @usedVariables.push value
      value = @readFloatOrPercent(@vars[value].value)

    if not /\d+/.test(value) and @defaultVars[value]?
      @usedVariables.push value
      value = @readFloatOrPercent(@defaultVars[value].value)

    return NaN unless value?
    return value if typeof value is 'number'

    if value.indexOf('%') isnt -1
      res = parseFloat(value) / 100
    else
      res = parseFloat(value)
      res = res / 100 if res > 1
      res

    res

  ##    ##     ## ######## #### ##        ######
  ##    ##     ##    ##     ##  ##       ##    ##
  ##    ##     ##    ##     ##  ##       ##
  ##    ##     ##    ##     ##  ##        ######
  ##    ##     ##    ##     ##  ##             ##
  ##    ##     ##    ##     ##  ##       ##    ##
  ##     #######     ##    #### ########  ######

  SVGColors: SVGColors

  Color: Color

  BlendModes: BlendModes

  split: (value) -> split(value)

  clamp: (value) -> clamp(value)

  clampInt: (value) -> clampInt(value)

  isInvalid: (color) -> not Color.isValid(color)

  readParam: (param, block) ->
    re = ///\$(\w+):\s*((-?#{@float})|#{@variablesRE})///
    if re.test(param)
      [_, name, value] = re.exec(param)

      block(name, value)

  contrast: (base, dark=new Color('black'), light=new Color('white'), threshold=0.43) ->
    [light, dark] = [dark, light] if dark.luma > light.luma

    if base.luma > threshold
      dark
    else
      light

  mixColors: (color1, color2, amount=0.5, round=Math.floor) ->
    return new Color(NaN, NaN, NaN, NaN) unless color1? and color2? and not isNaN(amount)

    inverse = 1 - amount
    color = new Color

    color.rgba = [
      round(color1.red * amount + color2.red * inverse)
      round(color1.green * amount + color2.green * inverse)
      round(color1.blue * amount + color2.blue * inverse)
      color1.alpha * amount + color2.alpha * inverse
    ]

    color

  ##    ########  ########  ######   ######## ##     ## ########
  ##    ##     ## ##       ##    ##  ##        ##   ##  ##     ##
  ##    ##     ## ##       ##        ##         ## ##   ##     ##
  ##    ########  ######   ##   #### ######      ###    ########
  ##    ##   ##   ##       ##    ##  ##         ## ##   ##
  ##    ##    ##  ##       ##    ##  ##        ##   ##  ##
  ##    ##     ## ########  ######   ######## ##     ## ##

  int: int

  float: float

  percent: percent

  optionalPercent: optionalPercent

  intOrPercent: intOrPercent

  floatOrPercent: floatOrPercent

  comma: comma

  notQuote: notQuote

  hexadecimal: hexadecimal

  ps: ps

  pe: pe

  variablesRE: variables

  namePrefixes: namePrefixes

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Jean Paul
-- Create date: 11/07/2019
-- Description:	Gera o cartão de ponto fazendo as críticas.
-- =============================================
-- ATUALIZAÇÕES
-- =============================================
-- Author:		Jean Paul
-- alter date: 30/07/2019
-- 1º Trocado a SP incluiOcorrencias de lugar, para dentro do cursor de dias pois quando funcionário em mais de um acordo coletivo, chama a SP mais de uma vez.
-- 2º alter date: 08/08/2019 Implementado os campos relacionados a lei do motorista
-- alter date: 21/08/2019
-- 1º Alterado a forma de verificar se o funcionário possui escala vinculada para uma forma mais eficaz.
-- alter date: 23/08/2019
-- 1º Implementado a SP que atualiza o saldo e o saldo anterior do funcionário no CP
-- =============================================
ALTER PROCEDURE [dbo].[spug_gerarCartaodePonto] 
	-- Add the parameters for the function here
	@funcicodigo int,@mes smallint, @ano int, @usuarcodigo int
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	-- VARIÁVEIS
	DECLARE
	@periodoiniciodatabase datetime, 
	@periodofimdatabase datetime, 
	@escala_vinculada bit = 0,
	@mov_or_cc_bloq bit,
	@func_ativo bit = 0,
	@sit_f char(2),
	@cartacodigo int,
	-- VARIÁVEIS USADAS NO CURSOR DE DADOS HISTÓRICOS
	@dia smallint,
	@dt date,
	@codigo_h int,
	@indicacao char(20),
	@cod_escala int,
	@ctococodigo int,
	@centccodigo int,
	@feriado bit,
	@feriatipo char(1),
	@acordcodigo int,
	@cargocodigo int,
	@tpapocodigo int,
	@flagocorrencia bit,
	@count int,
	@nacional bit,
	@municipal bit,
	@regional bit,
	@jornadalivre bit,
	@inicionoturno datetime,
	@fimnoturno datetime,
	@fatornoturno float,
	@estendenoturno bit,
	@cartaadn int,
	@cartacargahoraria int,
	@carta_previsto_e1 datetime,
	@carta_previsto_s1 datetime,
	@carta_previsto_e2 datetime,
	@carta_previsto_s2 datetime,
	@carta_previsto_e3 datetime,
	@carta_previsto_s3 datetime,
	@carta_previsto_e4 datetime,
	@carta_previsto_s4 datetime,
	@carta_realizado_e1 datetime, 
	@carta_realizado_s1 datetime,
	@carta_realizado_e2 datetime, 
	@carta_realizado_s2 datetime,
	@carta_realizado_e3 datetime, 
	@carta_realizado_s3 datetime,
	@carta_realizado_e4 datetime, 
	@carta_realizado_s4 datetime,
	@carta_justificativa_e1 int,
	@carta_justificativa_s1 int,
	@carta_justificativa_e2 int,
	@carta_justificativa_s2 int,
	@carta_justificativa_e3 int,
	@carta_justificativa_s3 int,
	@carta_justificativa_e4 int,
	@carta_justificativa_s4 int,
	@carta_tolerancia_anterior_e1 int, 
	@carta_tolerancia_posterior_e1 int, 
	@carta_tolerancia_anterior_s1 int, 
	@carta_tolerancia_posterior_s1 int,
	@carta_tolerancia_anterior_e2 int, 
	@carta_tolerancia_posterior_e2 int, 
	@carta_tolerancia_anterior_s2 int, 
	@carta_tolerancia_posterior_s2 int,
	@carta_tolerancia_anterior_e3 int, 
	@carta_tolerancia_posterior_e3 int, 
	@carta_tolerancia_anterior_s3 int, 
	@carta_tolerancia_posterior_s3 int,
	@carta_tolerancia_anterior_e4 int, 
	@carta_tolerancia_posterior_e4 int, 
	@carta_tolerancia_anterior_s4 int, 
	@carta_tolerancia_posterior_s4 int,
	@cartacargahorariarealizada int, 
	@cartahorasfalta int, 
	@horapontodecorte int,
	@minutopontodecorte int,
	@datapontodecorte datetime ,
	@pis char(11),
	@aptr datetime,
	@num int,
	@ult_apt_anterior datetime = NULL,
	@ult_apt datetime = NULL,
	@dt_auxiliar datetime = NULL,
	@horaespera int = NULL,
	@horaparada int = NULL,
	@horadirecao int = NULL,
	@horaintervcpl int = NULL,
	@horaintervsdesc int = NULL,
	@horainterjornadacompl int = NULL,
	@horainterjornadacomplsdesc int = NULL,
	@leimotorista bit, -- INFORMA SE FUNCIONÁRIO É OU NÃO LEI DO MOTORISTA
	-- INFORMA SE FUNCIONÁRIO É OU NÃO BANCO DE HORAS BASEADO NO DADO HISTÓRICO. ALTERAÇÃO FEITA EM 01/06/2020 POR JEAN PAUL.
	@bancodehoras bit,
	@contjornada int,
	@compljornada int, -- INFORMA SE EVENTO COMPLEMENTA OU NÃO A JORNADA DO DIA
	@afdtgcodigo int, @afdtgcodigo_e1 int,@afdtgcodigo_s1 int,@afdtgcodigo_e2 int,@afdtgcodigo_s2 int,@afdtgcodigo_e3 int,@afdtgcodigo_s3 int,@afdtgcodigo_e4 int,@afdtgcodigo_s4 int,
	@cartadesconsiderapreassinalado bit, @horarcodigo int, @h_referencia smallint

	select @sit_f = funcscodigo, @pis = funcipis /*@leimotorista = coalesce(funcileimotorista,0),*/ from tbgabfuncionario (nolock) where funcicodigo = @funcicodigo
	
	-- DECLARAÇÃO DA TABELA DE CARTÃO DE PONTO
	DECLARE @cartaodeponto table (sem_mov_or_cc_bloq bit,escala_vinculada bit,func_ativo bit,periodoinicio datetime, periodofim datetime)

	-- PERÍODO INÍCIO E FIM DE MOVIMENTAÇÃO
	select @periodoiniciodatabase = min(perioiniciodatabase),@periodofimdatabase = max(periofimdatabase) from tbgabperiodomovimentacao (nolock) 
	where centccodigo in (select centccodigo from tbgabcentrocustofuncionario (nolock) where funcicodigo = @funcicodigo) 
	and dbo.verificaCentrocustoBloqueado(perioiniciodatabase,centccodigo) = 0 
	and periomesbase = @mes 
	and perioanobase = @ano 
	and (centccodigo in (
	select centccodigo from tbgabresponsavelcentrocustoassoc RC (nolock)
	inner join tbgabresponsavelcentrocusto R on RC.respccodigo=R.respccodigo
	where R.usuarcodigo = @usuarcodigo) or 
	((select usuargestorsistema from tbgabusuario (nolock) where usuarcodigo = @usuarcodigo) = 1)) 
	
	-- SITUAÇÃO 1 -> CARTÃO DE PONTO SEM PERÍODO DE MOVIMENTAÇÃO PARA A DATA INFORMADA OU CENTRO DE CUSTO BLOQUEADO
	if @periodoiniciodatabase is null or @periodofimdatabase is null
	begin
		set @mov_or_cc_bloq = 1
		insert into @cartaodeponto values (@mov_or_cc_bloq,NULL,NULL,NULL,NULL)
	end

	-- SITUAÇÃO 0 -> CARTÃO DE PONTO COM PERÍODO DE MOVIMENTAÇÃO PARA A DATA INFORMADA E CENTRO DE CUSTO NÃO SE ENCONTRA BLOQUEADO
	else
	begin
		set @mov_or_cc_bloq = 0
		set @escala_vinculada = (select case when count(fuesccodigo) > 0 then 1 else 0 end from tbgabfuncionarioescala (nolock) 
								 where funcicodigo = @funcicodigo and fuescdatainiciovigencia <= @periodoiniciodatabase)

		-- SE NÃO POSSUI ESCALA VINCULADA PARA O PERÍODO INFORMADO
		if @escala_vinculada = 0
		begin
			insert into @cartaodeponto values (@mov_or_cc_bloq,@escala_vinculada,NULL,@periodoiniciodatabase,@periodofimdatabase)
		end

		-- SE POSSUI ESCALA VINCULADA PARA O PERÍODO INFORMADO
		else
		begin

			declare @datademissao datetime,@dataadmissao datetime
			select top 1 @datademissao=funcidatademissao,@dataadmissao=coalesce(funcidataadmissao,'1900-01-01') from tbgabfuncionario (nolock) where funcicodigo = @funcicodigo
			
			if (coalesce(@datademissao,'1900-01-01 00:00:00.000') = '1900-01-01 00:00:00.000')
			begin
				set @datademissao = @periodofimdatabase
			end

			declare @recalcular bit = (select recalcular from dbo.verificarRecalculoCP(@funcicodigo,@periodoiniciodatabase,@periodofimdatabase,@mes,@ano))

			-- ALTERAÇÃO 12/06/2020. ID DA DEMANDA: 36
			/* CÓDIGO IMPLEMENTADO */
			-- INÍCIO
			select @leimotorista = dbo.retornarSituacaoLeiMotoristaFuncionario(@funcicodigo,@periodoiniciodatabase,@periodofimdatabase)
			select @bancodehoras = dbo.retornarSituacaoBhFuncionario(@funcicodigo,@periodofimdatabase)
			-- FIM
			if (@datademissao not between @periodoiniciodatabase and @periodofimdatabase and @datademissao is not null and @datademissao > @periodofimdatabase) or @datademissao = '1900-01-01 00:00'
			begin
				set @datademissao = @periodofimdatabase
			end
			set @func_ativo = 1
			delete from tbgabcartaototalizador where funcicodigo = @funcicodigo and cartomesbase = @mes and cartoanobase = @ano and catcartocodigo in (9,10,14,15,17,114,115)
			
			-- RETORNAR DADOS HISTÓRICOS DO FUNCIONÁRIO	
			declare @dados_historicos table (pk int, dia int, dt datetime, codigo_h int, indicacao char(20), cod_escala int, ctococodigo int, centccodigo int, feriado bit, feriatipo char(1), acordcodigo int, cargocodigo int, tpapocodigo int, flagocorrencia bit)
			insert into @dados_historicos  select	
			ROW_NUMBER () OVER (ORDER BY dt),
			dia,
			dt,
			coalesce(codigo_h,0),	
			indicacao,
			cod_escala,
			coalesce(CO.ctococodigo,0),
			coalesce(centccodigo,0),
			feriado,
			feriatipo,
			coalesce(acordcodigo,0),
			coalesce(cargocodigo,0),
			coalesce(tpapocodigo,0),
			flagocorrencia
			from dbo.retornarDadosHistoricosFuncionario(@funcicodigo,@periodoiniciodatabase,@periodofimdatabase)
			left join tbgabcartaoocorrencia CO (nolock) on dbo.retornarDadosHistoricosFuncionario.indicacao=CO.ctocodescricao

			declare @pk int = 1, @totalRows int = (select count(dia) from @dados_historicos)
			while @pk <= @totalRows
			begin
				select @dia=dia,@dt=dt,@codigo_h=codigo_h,@indicacao=indicacao,@cod_escala=cod_escala,@ctococodigo=ctococodigo,@centccodigo=centccodigo,@feriado=feriado,@feriatipo=feriatipo,@acordcodigo=acordcodigo,@cargocodigo=cargocodigo,@tpapocodigo=tpapocodigo,@flagocorrencia=flagocorrencia
				from @dados_historicos where pk = @pk

				set @cartacodigo = null
				set @cartacodigo = (select top 1 cartacodigo from tbgabcartaodeponto where cartadatajornada = @dt and funcicodigo = @funcicodigo)
				set @cartacargahorariarealizada = NULL
				set @cartacargahoraria = NULL
				set @carta_realizado_e1 = NULL
				set @carta_realizado_s1 = NULL
				set @carta_realizado_e2 = NULL
				set @carta_realizado_s2 = NULL
				set @carta_realizado_e3 = NULL
				set @carta_realizado_s3 = NULL
				set @carta_realizado_e4 = NULL
				set @carta_realizado_s4 = NULL
				set @carta_previsto_e1 = NULL
				set @carta_previsto_s1 = NULL
				set @carta_previsto_e2 = NULL
				set @carta_previsto_s2 = NULL
				set @carta_previsto_e3 = NULL
				set @carta_previsto_s3 = NULL
				set @carta_previsto_e4 = NULL
				set @carta_previsto_s4 = NULL
				set @carta_tolerancia_anterior_e1=NULL
				set @carta_tolerancia_anterior_s1=NULL
				set @carta_tolerancia_posterior_e1=NULL
				set @carta_tolerancia_posterior_s1=NULL
				set @carta_tolerancia_anterior_e2=NULL
				set @carta_tolerancia_anterior_s2=NULL
				set @carta_tolerancia_posterior_e2=NULL
				set @carta_tolerancia_posterior_s2=NULL
				set @carta_tolerancia_anterior_e3=NULL
				set @carta_tolerancia_anterior_s3=NULL
				set @carta_tolerancia_posterior_e3=NULL
				set @carta_tolerancia_posterior_s3=NULL
				set @carta_tolerancia_anterior_e4=NULL
				set @carta_tolerancia_anterior_s4=NULL
				set @carta_tolerancia_posterior_e4=NULL
				set @carta_tolerancia_posterior_s4=NULL

				-- VERIFICA SE NÃO EXISTE UM REGISTRO PARA O DIA CORRENTE
				if @cartacodigo is null
				begin
					if @dataadmissao <= @dt and @dt <= @datademissao
					begin
						set @nacional = 0
						set @regional = 0
						set @municipal = 0
						-- VERIFICA SE O DIA É FERIADO E QUAL O TIPO DE FERIADO
						if @feriado = 1
						begin
							if @feriatipo = 'N' begin set @nacional = 1 end
							if @feriatipo = 'M' begin set @municipal = 1 end
							if @feriatipo = 'R' begin set @regional = 1 end
						end
						
						-- SE NÃO HÁ ACORDO COLETIVO PARA O DIA
						if @acordcodigo = 0
						begin
							-- SE A INDICAÇÃO PARA O DIA FOR <> DE TRABALHO
							if @indicacao <> 'Trabalho'
							begin
								set @jornadalivre = 1
							end
							-- SE A INDICAÇÃO PARA O DIA FOR = TRABALHO
							else
							begin
								set @jornadalivre = null
							end
							set @inicionoturno = null
							set @fimnoturno = null
							set @fatornoturno = null
							set @estendenoturno = null
							set @cartaadn = 0
						end

						-- SE HÁ ACORDO COLETIVO PARA O DIA
						else
						begin	
							-- SE A INDICAÇÃO FOR FOLGA OU DSR.
							if @ctococodigo = 2 or @ctococodigo = 3 
							begin 
								set @jornadalivre = 1
							end
							else
							begin
								set @jornadalivre = (select acordjornadalivre from tbgabacordocoletivo (nolock) where acordcodigo = @acordcodigo)
							end
							select 
							@inicionoturno=inicionoturno,
							@fimnoturno=fimnoturno,
							@fatornoturno=fatornoturno,
							@estendenoturno=estendenoturno from dbo.retornarInicioFimNoturno(@acordcodigo,@dt)
							set @cartaadn = 0
						end
						
						-- SE HÁ HORÁRIO PARA O DIA
						if @codigo_h <> 0
						begin
							select 
							@cartacargahoraria=horarcargahoraria,
							@carta_tolerancia_anterior_e1=horartoleranciaanteriorentrada1,
							@carta_tolerancia_anterior_s1=horartoleranciaanteriorsaida1,
							@carta_tolerancia_posterior_e1=horartoleranciaposteriorentrada1,
							@carta_tolerancia_posterior_s1=horartoleranciaposteriorsaida1,
							@carta_tolerancia_anterior_e2=horartoleranciaanteriorentrada2,
							@carta_tolerancia_anterior_s2=horartoleranciaanteriorsaida2,
							@carta_tolerancia_posterior_e2=horartoleranciaposteriorentrada2,
							@carta_tolerancia_posterior_s2=horartoleranciaposteriorsaida2,
							@carta_tolerancia_anterior_e3=horartoleranciaanteriorentrada3,
							@carta_tolerancia_anterior_s3=horartoleranciaanteriorsaida3,
							@carta_tolerancia_posterior_e3=horartoleranciaposteriorentrada3,
							@carta_tolerancia_posterior_s3=horartoleranciaposteriorsaida3,
							@carta_tolerancia_anterior_e4=horartoleranciaanteriorentrada4,
							@carta_tolerancia_anterior_s4=horartoleranciaanteriorsaida4,
							@carta_tolerancia_posterior_e4=horartoleranciaposteriorentrada4,
							@carta_tolerancia_posterior_s4=horartoleranciaposteriorsaida4
							from tbgabhorario (nolock) where horarcodigo = @codigo_h

							select 
							@carta_previsto_e1=e1,@carta_previsto_s1=s1,
							@carta_previsto_e2=e2,@carta_previsto_s2=s2,
							@carta_previsto_e3=e3,@carta_previsto_s3=s3,
							@carta_previsto_e4=e4,@carta_previsto_s4=s4 
							from dbo.retornarHorariosPrevistos(@codigo_h,@dt)
						end 

						-- SE HÁ CONFLITO DE ESCALAS, MUDA A REFERÊNCIA DE HORÁRIO
						if dbo.retornarConflitoEscala(@dt,@funcicodigo,@carta_previsto_e1) = 1 begin set @h_referencia = 2 end else begin set @h_referencia = 1 end
						
						-- CURSOR PARA RODAR OS APTS REALIZADOS
						DECLARE realizadas CURSOR FOR
						-- ALTERAÇÃO 12/06/2020. ID DA DEMANDA: 36
						select horarios,num,afdtgcodigo from dbo.retornarApontamentosRealizadosComPreAssinalados2(@funcicodigo,@dt,@codigo_h,@jornadalivre,@ctococodigo,0,@h_referencia,/* CÓDIGO ALTERADO */@leimotorista/* CÓDIGO ALTERADO */)
						OPEN realizadas
						FETCH NEXT FROM realizadas INTO @aptr,@num,@afdtgcodigo
						WHILE @@FETCH_STATUS = 0
						BEGIN
									if @num = 1 begin set @carta_realizado_e1 = @aptr set @afdtgcodigo_e1 = @afdtgcodigo end
							else if @num = 2 begin set @carta_realizado_s1 = @aptr set @afdtgcodigo_s1 = @afdtgcodigo end
							else if @num = 3 begin set @carta_realizado_e2 = @aptr set @afdtgcodigo_e2 = @afdtgcodigo end
							else if @num = 4 begin set @carta_realizado_s2 = @aptr set @afdtgcodigo_s2 = @afdtgcodigo end
							else if @num = 5 begin set @carta_realizado_e3 = @aptr set @afdtgcodigo_e3 = @afdtgcodigo end
							else if @num = 6 begin set @carta_realizado_s3 = @aptr set @afdtgcodigo_s3 = @afdtgcodigo end
							else if @num = 7 begin set @carta_realizado_e4 = @aptr set @afdtgcodigo_e4 = @afdtgcodigo end
							else if @num = 8 begin set @carta_realizado_s4 = @aptr set @afdtgcodigo_s4 = @afdtgcodigo end
						FETCH NEXT FROM realizadas INTO @aptr,@num,@afdtgcodigo
						END
						CLOSE realizadas
						DEALLOCATE realizadas

						-- TESTA SE O FUNCIONÁRIO É LEI DO MOTORISTA
						if @leimotorista = 1 
						begin 
							set @horaespera = (select sum(horasespera) from dbo.retornarTempoEsperaLeidoMotorista(@pis,@dt))
							set @horaparada = (select sum(horasparada) from dbo.retornarTempoParadaLeidoMotorista(@pis,@dt))
							set @horadirecao = (select sum(horasdirecao) from dbo.retornarTempoDirecaoLeidoMotorista(@pis,@dt))
							set @horaintervcpl = (select sum(horasintervcpl) from dbo.retornarTempoIntervCplLeidoMotorista(@pis,@dt))
							set @horaintervsdesc = (select sum(horasintervsemdesc) from dbo.retornarTempoIntervSemDescLeidoMotorista(@pis,@dt))
							set @horainterjornadacompl = (select sum(horasinterjornadacompl) from dbo.retornarTempoInterjornadaComplLeidoMotorista(@pis,@dt))
							set @horainterjornadacomplsdesc = (select SUM(horasinterjornadasdesc) from dbo.retornarTempoInterjornadaSemDescLeidoMotorista(@pis,@dt))
						end

						begin
						try
							-- INSERE
							insert into tbgabcartaodeponto (
							cartadatajornada,
							cargocodigo,
							ctococodigo,
							funcicodigo,
							acordcodigo,
							cartadiasemana,
							cartacargahoraria,
							carta_previsto_e1,
							carta_previsto_s1,
							carta_previsto_e2,
							carta_previsto_s2,
							carta_previsto_e3,
							carta_previsto_s3,
							carta_previsto_e4,
							carta_previsto_s4,
							cartaferiadonacional,										
							cartaferiadoregional,
							cartaferiadomunicipal,
							centccodigo,
							cartamesbase,
							cartaanobase,
							carta_realizado_e1,
							carta_realizado_s1,
							carta_realizado_e2,
							carta_realizado_s2,
							carta_realizado_e3,
							carta_realizado_s3,
							carta_realizado_e4,
							carta_realizado_s4,
							cartainicionoturno,
							cartafimnoturno,
							cartafatornoturno,
							cartaestendenoturno,
							cartajornadalivre,
							cartaadn,
							carta_tolerancia_anterior_e1,
							carta_tolerancia_posterior_e1,
							carta_tolerancia_anterior_s1,
							carta_tolerancia_posterior_s1,
							carta_tolerancia_anterior_e2,
							carta_tolerancia_posterior_e2,
							carta_tolerancia_anterior_s2,
							carta_tolerancia_posterior_s2,
							carta_tolerancia_anterior_e3,
							carta_tolerancia_posterior_e3,
							carta_tolerancia_anterior_s3,
							carta_tolerancia_posterior_s3,
							carta_tolerancia_anterior_e4,
							carta_tolerancia_posterior_e4,
							carta_tolerancia_anterior_s4,
							carta_tolerancia_posterior_s4,
							cartaflagferiado,
							cartaflagocorrencia,
							ctococodigooriginal,
							horarcodigo,
							horarcodigooriginal,
							cartasaldoanteriorbh,
							cartacreditobh,
							cartadebitobh,
							cartasaldoatualbh,
							cartaespera,
							cartaparada,
							cartadirecao,
							cartaintervcpl,
							cartaintervsdesc,
							cartainterjornadacompl,
							cartainterjornadacomplsdesc,
							afdtgcodigo_e1,afdtgcodigo_s1,afdtgcodigo_e2,afdtgcodigo_s2,afdtgcodigo_e3,afdtgcodigo_s3,afdtgcodigo_e4,afdtgcodigo_s4,cartahorarreferencia
							) 
							values (
							@dt,
							@cargocodigo,
							@ctococodigo,
							@funcicodigo,
							@acordcodigo,
							@dia,
							@cartacargahoraria,
							@carta_previsto_e1,
							@carta_previsto_s1,
							@carta_previsto_e2,
							@carta_previsto_s2,
							@carta_previsto_e3,
							@carta_previsto_s3,
							@carta_previsto_e4,
							@carta_previsto_s4,
							@nacional,
							@regional,
							@municipal,
							@centccodigo,
							@mes,
							@ano,
							@carta_realizado_e1,
							@carta_realizado_s1,
							@carta_realizado_e2,
							@carta_realizado_s2,
							@carta_realizado_e3,
							@carta_realizado_s3,
							@carta_realizado_e4,
							@carta_realizado_s4,
							@inicionoturno,
							@fimnoturno,
							@fatornoturno,
							@estendenoturno,
							@jornadalivre,
							@cartaadn,
							@carta_tolerancia_anterior_e1,
							@carta_tolerancia_posterior_e1,
							@carta_tolerancia_anterior_s1,
							@carta_tolerancia_posterior_s1,
							@carta_tolerancia_anterior_e2,
							@carta_tolerancia_posterior_e2,
							@carta_tolerancia_anterior_s2,
							@carta_tolerancia_posterior_s2,
							@carta_tolerancia_anterior_e3,
							@carta_tolerancia_posterior_e3,
							@carta_tolerancia_anterior_s3,
							@carta_tolerancia_posterior_s3,
							@carta_tolerancia_anterior_e4,
							@carta_tolerancia_posterior_e4,
							@carta_tolerancia_anterior_s4,
							@carta_tolerancia_posterior_s4,
							@feriado,
							@flagocorrencia,
							@ctococodigo,
							@codigo_h,
							@codigo_h,
							null,
							null,
							null,
							null,
							@horaespera,
							@horaparada,
							@horadirecao,
							@horaintervcpl,
							@horaintervsdesc,
							@horainterjornadacompl,
							@horainterjornadacomplsdesc,@afdtgcodigo_e1,@afdtgcodigo_s1,@afdtgcodigo_e2,@afdtgcodigo_s2,@afdtgcodigo_e3,@afdtgcodigo_s3,@afdtgcodigo_e4,@afdtgcodigo_s4,@h_referencia)

							set @cartacodigo = (select cartacodigo from tbgabcartaodeponto (nolock) where funcicodigo = @funcicodigo and cartadatajornada = @dt)
							-- PEGA HORA REALIZADA
							set @cartacargahorariarealizada = (select minuto from dbo.retornarSomaHorasFuncionario(@cartacodigo))

							-- ATUALIZA HORA REALIZADA
							update tbgabcartaodeponto set cartacargahorariarealizada = @cartacargahorariarealizada where cartacodigo = @cartacodigo

							-- INCLUI TOTALIZADORES
							exec dbo.spug_incluirTotalizadores @acordcodigo, @funcicodigo, @dt, 'spug_gerarCartaodePonto_background_insert'

							-- ATUALIZA HORAS FALTA
							set @cartahorasfalta = (select horasfalta from dbo.retornarSomaHorasFuncionario(@cartacodigo))
							update tbgabcartaodeponto set 
							cartahorasfalta = @cartahorasfalta
							where cartacodigo = @cartacodigo
						
							-- INSERE
							insert into @cartaodeponto values (
							@mov_or_cc_bloq, -- 1
							@escala_vinculada, -- 2
							@func_ativo, -- 3
							@periodoiniciodatabase, -- 4
							@periodofimdatabase) -- 5
						end try
						begin catch
							insert into tbgabduplicados (funcicodigo,datajornada,rotina_origem,usuarcadastro,error)
							values (@funcicodigo,@dt,'spug_gerarCartaodePonto_background_insert',@usuarcodigo,ERROR_MESSAGE())
						end catch;
					end
					else
					begin
						set @nacional = 0
						set @regional = 0
						set @municipal = 0
						-- VERIFICA SE O DIA É FERIADO E QUAL O TIPO DE FERIADO
						if @feriado = 1
						begin
							if @feriatipo = 'N' begin set @nacional = 1 end
							if @feriatipo = 'M' begin set @municipal = 1 end
							if @feriatipo = 'R' begin set @regional = 1 end
						end
						
						-- SE NÃO HÁ ACORDO COLETIVO PARA O DIA
						if @acordcodigo = 0
						begin
							-- SE A INDICAÇÃO PARA O DIA FOR <> DE TRABALHO
							if @indicacao <> 'Trabalho'
							begin
								set @jornadalivre = 1
							end
							-- SE A INDICAÇÃO PARA O DIA FOR = TRABALHO
							else
							begin
								set @jornadalivre = null
							end
							set @inicionoturno = null
							set @fimnoturno = null
							set @fatornoturno = null
							set @estendenoturno = null
							set @cartaadn = 0
						end

						-- SE HÁ ACORDO COLETIVO PARA O DIA
						else
						begin	
							-- SE A INDICAÇÃO FOR FOLGA OU DSR.
							if @ctococodigo = 2 or @ctococodigo = 3 
							begin 
								set @jornadalivre = 1
							end
							else
							begin
								set @jornadalivre = (select acordjornadalivre from tbgabacordocoletivo (nolock) where acordcodigo = @acordcodigo)
							end
							select 
							@inicionoturno=inicionoturno,
							@fimnoturno=fimnoturno,
							@fatornoturno=fatornoturno,
							@estendenoturno=estendenoturno from dbo.retornarInicioFimNoturno(@acordcodigo,@dt)
							set @cartaadn = 0
						end
						
						-- SE HÁ HORÁRIO PARA O DIA
						if @codigo_h <> 0
						begin
							select 
							@cartacargahoraria=horarcargahoraria,
							@carta_tolerancia_anterior_e1=horartoleranciaanteriorentrada1,
							@carta_tolerancia_anterior_s1=horartoleranciaanteriorsaida1,
							@carta_tolerancia_posterior_e1=horartoleranciaposteriorentrada1,
							@carta_tolerancia_posterior_s1=horartoleranciaposteriorsaida1,
							@carta_tolerancia_anterior_e2=horartoleranciaanteriorentrada2,
							@carta_tolerancia_anterior_s2=horartoleranciaanteriorsaida2,
							@carta_tolerancia_posterior_e2=horartoleranciaposteriorentrada2,
							@carta_tolerancia_posterior_s2=horartoleranciaposteriorsaida2,
							@carta_tolerancia_anterior_e3=horartoleranciaanteriorentrada3,
							@carta_tolerancia_anterior_s3=horartoleranciaanteriorsaida3,
							@carta_tolerancia_posterior_e3=horartoleranciaposteriorentrada3,
							@carta_tolerancia_posterior_s3=horartoleranciaposteriorsaida3,
							@carta_tolerancia_anterior_e4=horartoleranciaanteriorentrada4,
							@carta_tolerancia_anterior_s4=horartoleranciaanteriorsaida4,
							@carta_tolerancia_posterior_e4=horartoleranciaposteriorentrada4,
							@carta_tolerancia_posterior_s4=horartoleranciaposteriorsaida4
							from tbgabhorario (nolock) where horarcodigo = @codigo_h

							select 
							@carta_previsto_e1=e1,@carta_previsto_s1=s1,
							@carta_previsto_e2=e2,@carta_previsto_s2=s2,
							@carta_previsto_e3=e3,@carta_previsto_s3=s3,
							@carta_previsto_e4=e4,@carta_previsto_s4=s4 
							from dbo.retornarHorariosPrevistos(@codigo_h,@dt)
						end 

						-- SE HÁ CONFLITO DE ESCALAS, MUDA A REFERÊNCIA DE HORÁRIO
						if dbo.retornarConflitoEscala(@dt,@funcicodigo,@carta_previsto_e1) = 1 begin set @h_referencia = 2 end else begin set @h_referencia = 1 end
						
						-- CURSOR PARA RODAR OS APTS REALIZADOS
						DECLARE realizadas CURSOR FOR
						-- ALTERAÇÃO 12/06/2020. ID DA DEMANDA: 36
						select horarios,num,afdtgcodigo from dbo.retornarApontamentosRealizadosComPreAssinalados2(@funcicodigo,@dt,@codigo_h,@jornadalivre,@ctococodigo,0,@h_referencia,/* CÓDIGO ALTERADO */@leimotorista/* CÓDIGO ALTERADO */)
						OPEN realizadas
						FETCH NEXT FROM realizadas INTO @aptr,@num,@afdtgcodigo
						WHILE @@FETCH_STATUS = 0
						BEGIN
									if @num = 1 begin set @carta_realizado_e1 = @aptr set @afdtgcodigo_e1 = @afdtgcodigo end
							else if @num = 2 begin set @carta_realizado_s1 = @aptr set @afdtgcodigo_s1 = @afdtgcodigo end
							else if @num = 3 begin set @carta_realizado_e2 = @aptr set @afdtgcodigo_e2 = @afdtgcodigo end
							else if @num = 4 begin set @carta_realizado_s2 = @aptr set @afdtgcodigo_s2 = @afdtgcodigo end
							else if @num = 5 begin set @carta_realizado_e3 = @aptr set @afdtgcodigo_e3 = @afdtgcodigo end
							else if @num = 6 begin set @carta_realizado_s3 = @aptr set @afdtgcodigo_s3 = @afdtgcodigo end
							else if @num = 7 begin set @carta_realizado_e4 = @aptr set @afdtgcodigo_e4 = @afdtgcodigo end
							else if @num = 8 begin set @carta_realizado_s4 = @aptr set @afdtgcodigo_s4 = @afdtgcodigo end
						FETCH NEXT FROM realizadas INTO @aptr,@num,@afdtgcodigo
						END
						CLOSE realizadas
						DEALLOCATE realizadas

						-- TESTA SE O FUNCIONÁRIO É LEI DO MOTORISTA
						if @leimotorista = 1 
						begin 
							set @horaespera = (select sum(horasespera) from dbo.retornarTempoEsperaLeidoMotorista(@pis,@dt))
							set @horaparada = (select sum(horasparada) from dbo.retornarTempoParadaLeidoMotorista(@pis,@dt))
							set @horadirecao = (select sum(horasdirecao) from dbo.retornarTempoDirecaoLeidoMotorista(@pis,@dt))
							set @horaintervcpl = (select sum(horasintervcpl) from dbo.retornarTempoIntervCplLeidoMotorista(@pis,@dt))
							set @horaintervsdesc = (select sum(horasintervsemdesc) from dbo.retornarTempoIntervSemDescLeidoMotorista(@pis,@dt))
							set @horainterjornadacompl = (select sum(horasinterjornadacompl) from dbo.retornarTempoInterjornadaComplLeidoMotorista(@pis,@dt))
							set @horainterjornadacomplsdesc = (select SUM(horasinterjornadasdesc) from dbo.retornarTempoInterjornadaSemDescLeidoMotorista(@pis,@dt))
						end

						begin
						try
							-- INSERE
							insert into tbgabcartaodeponto (
							cartadatajornada,
							cargocodigo,
							ctococodigo,
							funcicodigo,
							acordcodigo,
							cartadiasemana,
							cartacargahoraria,
							carta_previsto_e1,
							carta_previsto_s1,
							carta_previsto_e2,
							carta_previsto_s2,
							carta_previsto_e3,
							carta_previsto_s3,
							carta_previsto_e4,
							carta_previsto_s4,
							cartaferiadonacional,										
							cartaferiadoregional,
							cartaferiadomunicipal,
							centccodigo,
							cartamesbase,
							cartaanobase,
							carta_realizado_e1,
							carta_realizado_s1,
							carta_realizado_e2,
							carta_realizado_s2,
							carta_realizado_e3,
							carta_realizado_s3,
							carta_realizado_e4,
							carta_realizado_s4,
							cartainicionoturno,
							cartafimnoturno,
							cartafatornoturno,
							cartaestendenoturno,
							cartajornadalivre,
							cartaadn,
							carta_tolerancia_anterior_e1,
							carta_tolerancia_posterior_e1,
							carta_tolerancia_anterior_s1,
							carta_tolerancia_posterior_s1,
							carta_tolerancia_anterior_e2,
							carta_tolerancia_posterior_e2,
							carta_tolerancia_anterior_s2,
							carta_tolerancia_posterior_s2,
							carta_tolerancia_anterior_e3,
							carta_tolerancia_posterior_e3,
							carta_tolerancia_anterior_s3,
							carta_tolerancia_posterior_s3,
							carta_tolerancia_anterior_e4,
							carta_tolerancia_posterior_e4,
							carta_tolerancia_anterior_s4,
							carta_tolerancia_posterior_s4,
							cartaflagferiado,
							cartaflagocorrencia,
							ctococodigooriginal,
							horarcodigo,
							horarcodigooriginal,
							cartasaldoanteriorbh,
							cartacreditobh,
							cartadebitobh,
							cartasaldoatualbh,
							cartaespera,
							cartaparada,
							cartadirecao,
							cartaintervcpl,
							cartaintervsdesc,
							cartainterjornadacompl,
							cartainterjornadacomplsdesc,
							afdtgcodigo_e1,afdtgcodigo_s1,afdtgcodigo_e2,afdtgcodigo_s2,afdtgcodigo_e3,afdtgcodigo_s3,afdtgcodigo_e4,afdtgcodigo_s4,cartahorarreferencia
							) 
							values (
							@dt,
							@cargocodigo,
							@ctococodigo,
							@funcicodigo,
							@acordcodigo,
							@dia,
							@cartacargahoraria,
							@carta_previsto_e1,
							@carta_previsto_s1,
							@carta_previsto_e2,
							@carta_previsto_s2,
							@carta_previsto_e3,
							@carta_previsto_s3,
							@carta_previsto_e4,
							@carta_previsto_s4,
							@nacional,
							@regional,
							@municipal,
							@centccodigo,
							@mes,
							@ano,
							@carta_realizado_e1,
							@carta_realizado_s1,
							@carta_realizado_e2,
							@carta_realizado_s2,
							@carta_realizado_e3,
							@carta_realizado_s3,
							@carta_realizado_e4,
							@carta_realizado_s4,
							@inicionoturno,
							@fimnoturno,
							@fatornoturno,
							@estendenoturno,
							@jornadalivre,
							@cartaadn,
							@carta_tolerancia_anterior_e1,
							@carta_tolerancia_posterior_e1,
							@carta_tolerancia_anterior_s1,
							@carta_tolerancia_posterior_s1,
							@carta_tolerancia_anterior_e2,
							@carta_tolerancia_posterior_e2,
							@carta_tolerancia_anterior_s2,
							@carta_tolerancia_posterior_s2,
							@carta_tolerancia_anterior_e3,
							@carta_tolerancia_posterior_e3,
							@carta_tolerancia_anterior_s3,
							@carta_tolerancia_posterior_s3,
							@carta_tolerancia_anterior_e4,
							@carta_tolerancia_posterior_e4,
							@carta_tolerancia_anterior_s4,
							@carta_tolerancia_posterior_s4,
							@feriado,
							@flagocorrencia,
							@ctococodigo,
							@codigo_h,
							@codigo_h,
							null,
							null,
							null,
							null,
							@horaespera,
							@horaparada,
							@horadirecao,
							@horaintervcpl,
							@horaintervsdesc,
							@horainterjornadacompl,
							@horainterjornadacomplsdesc,@afdtgcodigo_e1,@afdtgcodigo_s1,@afdtgcodigo_e2,@afdtgcodigo_s2,@afdtgcodigo_e3,@afdtgcodigo_s3,@afdtgcodigo_e4,@afdtgcodigo_s4,@h_referencia)
						end try
						begin catch
							insert into tbgabduplicados (funcicodigo,datajornada,rotina_origem,usuarcadastro,error)
							values (@funcicodigo,@dt,'spug_gerarCartaodePonto_background_insert',@usuarcodigo,ERROR_MESSAGE())
						end catch;
					end
				end 
				
				-- VERIFICA SE JÁ EXISTE UM REGISTRO PARA O DIA CORRENTE
				else
				begin
					if @dataadmissao <= @dt and @dt <= @datademissao
					begin
						-- CHAVE PRIMÁRIA DA TABELA CARTÃO DE PONTO
						select top 1 @horarcodigo=horarcodigo,@cartadesconsiderapreassinalado=cartadesconsiderapreassinalado,@h_referencia=cartahorarreferencia from tbgabcartaodeponto (nolock) where cartacodigo = @cartacodigo

						-- SE NÃO HÁ ACORDO COLETIVO PARA O DIA
						if @acordcodigo = 0
						begin
							-- SE A INDICAÇÃO PARA O DIA FOR <> DE TRABALHO
							if @indicacao <> 'Trabalho'
							begin
								set @jornadalivre = 1
							end
							-- SE A INDICAÇÃO PARA O DIA FOR = TRABALHO
							else
							begin
								set @jornadalivre = null
							end
							set @inicionoturno = null
							set @fimnoturno = null
							set @fatornoturno = null
							set @estendenoturno = null
							set @cartaadn = 0
						end

						-- SE HÁ ACORDO COLETIVO PARA O DIA
						else
						begin
							-- SE A INDICAÇÃO FOR FOLGA OU DSR.
							if @ctococodigo = 2 or @ctococodigo = 3 
							begin 
								set @jornadalivre = 1
							end
							else
							begin
								set @jornadalivre = (select acordjornadalivre from tbgabacordocoletivo (nolock) where acordcodigo = @acordcodigo)
							end
							select 
							@inicionoturno=inicionoturno,
							@fimnoturno=fimnoturno,
							@fatornoturno=fatornoturno,
							@estendenoturno=estendenoturno from dbo.retornarInicioFimNoturno(@acordcodigo,@dt)
							set @cartaadn = 0
						end
						
						-- SE HÁ NOVOS APONTAMENTOS NA TABELA DE AFDT
						if @recalcular = 1
						begin
							set @nacional = 0
							set @regional = 0
							set @municipal = 0

							-- VERIFICA SE O DIA É FERIADO E QUAL O TIPO DE FERIADO
							if @feriado = 1
							begin
								if @feriatipo = 'N' begin set @nacional = 1 end
								if @feriatipo = 'M' begin set @municipal = 1 end
								if @feriatipo = 'R' begin set @regional = 1 end
							end

							-- CURSOR PARA RODAR OS APTS REALIZADOS
							DECLARE realizadas CURSOR FOR
							-- ALTERAÇÃO 12/06/2020. ID DA DEMANDA: 36
							select horarios,num,afdtgcodigo from dbo.retornarApontamentosRealizadosComPreAssinalados2(@funcicodigo,@dt,@horarcodigo,@jornadalivre,@ctococodigo,@cartadesconsiderapreassinalado,@h_referencia,/* CÓDIGO ALTERADO */@leimotorista/* CÓDIGO ALTERADO */)
							OPEN realizadas
							FETCH NEXT FROM realizadas INTO @aptr,@num,@afdtgcodigo
							WHILE @@FETCH_STATUS = 0
							BEGIN
										if @num = 1 begin set @carta_realizado_e1 = @aptr set @afdtgcodigo_e1 = @afdtgcodigo end
								else if @num = 2 begin set @carta_realizado_s1 = @aptr set @afdtgcodigo_s1 = @afdtgcodigo end
								else if @num = 3 begin set @carta_realizado_e2 = @aptr set @afdtgcodigo_e2 = @afdtgcodigo end
								else if @num = 4 begin set @carta_realizado_s2 = @aptr set @afdtgcodigo_s2 = @afdtgcodigo end
								else if @num = 5 begin set @carta_realizado_e3 = @aptr set @afdtgcodigo_e3 = @afdtgcodigo end
								else if @num = 6 begin set @carta_realizado_s3 = @aptr set @afdtgcodigo_s3 = @afdtgcodigo end
								else if @num = 7 begin set @carta_realizado_e4 = @aptr set @afdtgcodigo_e4 = @afdtgcodigo end
								else if @num = 8 begin set @carta_realizado_s4 = @aptr set @afdtgcodigo_s4 = @afdtgcodigo end
							FETCH NEXT FROM realizadas INTO @aptr,@num,@afdtgcodigo
							END
							CLOSE realizadas
							DEALLOCATE realizadas
								
							-- TESTA SE O FUNCIONÁRIO É LEI DO MOTORISTA
							if @leimotorista = 1 begin 
								set @horaespera = (select sum(horasespera) from dbo.retornarTempoEsperaLeidoMotorista(@pis,@dt))
								set @horaparada = (select sum(horasparada) from dbo.retornarTempoParadaLeidoMotorista(@pis,@dt))
								set @horadirecao = (select sum(horasdirecao) from dbo.retornarTempoDirecaoLeidoMotorista(@pis,@dt))
								set @horaintervcpl = (select sum(horasintervcpl) from dbo.retornarTempoIntervCplLeidoMotorista(@pis,@dt))
								set @horaintervsdesc = (select sum(horasintervsemdesc) from dbo.retornarTempoIntervSemDescLeidoMotorista(@pis,@dt))
								set @horainterjornadacompl = (select sum(horasinterjornadacompl) from dbo.retornarTempoInterjornadaComplLeidoMotorista(@pis,@dt))
								set @horainterjornadacomplsdesc = (select SUM(horasinterjornadasdesc) from dbo.retornarTempoInterjornadaSemDescLeidoMotorista(@pis,@dt))
							end

							-- UPDATE
							update tbgabcartaodeponto set
							cargocodigo = @cargocodigo,
							funcicodigo = @funcicodigo,
							acordcodigo = @acordcodigo,
							cartaferiadonacional = @nacional,										
							cartaferiadoregional = @regional,
							cartaferiadomunicipal = @municipal,
							centccodigo = @centccodigo,
							cartamesbase = @mes,
							cartaanobase = @ano,
							carta_realizado_e1 = @carta_realizado_e1,
							carta_realizado_s1 = @carta_realizado_s1,
							carta_realizado_e2 = @carta_realizado_e2,
							carta_realizado_s2 = @carta_realizado_s2,
							carta_realizado_e3 = @carta_realizado_e3,
							carta_realizado_s3 = @carta_realizado_s3,
							carta_realizado_e4 = @carta_realizado_e4,
							carta_realizado_s4 = @carta_realizado_s4,
							afdtgcodigo_e1 = @afdtgcodigo_e1,
							afdtgcodigo_s1 = @afdtgcodigo_s1,
							afdtgcodigo_e2 = @afdtgcodigo_e2,
							afdtgcodigo_s2 = @afdtgcodigo_s2,
							afdtgcodigo_e3 = @afdtgcodigo_e3,
							afdtgcodigo_s3 = @afdtgcodigo_s3,
							afdtgcodigo_e4 = @afdtgcodigo_e4,
							afdtgcodigo_s4 = @afdtgcodigo_s4,
							cartainicionoturno = @inicionoturno,
							cartafimnoturno = @fimnoturno,
							cartafatornoturno = @fatornoturno,
							cartaestendenoturno = @estendenoturno,
							cartajornadalivre = @jornadalivre,
							cartaadn = @cartaadn,
							cartaflagferiado = @feriado,
							cartaflagocorrencia = @flagocorrencia,
							cartasaldoanteriorbh = null,
							cartacreditobh = null,
							cartadebitobh = null,
							cartasaldoatualbh = null,
							cartaespera = @horaespera,
							cartaparada = @horaparada,
							cartadirecao = @horadirecao,
							cartaintervcpl = @horaintervcpl,
							cartaintervsdesc = @horaintervsdesc,
							cartainterjornadacompl = @horainterjornadacompl,
							cartainterjornadacomplsdesc = @horainterjornadacomplsdesc,
							cartahorasextra = null
							where cartacodigo = @cartacodigo

							-- PEGA HORA REALIZADA
							set @cartacargahorariarealizada = (select minuto from dbo.retornarSomaHorasFuncionario(@cartacodigo))

							-- ATUALIZA HORA REALIZADA
							update tbgabcartaodeponto set cartacargahorariarealizada = @cartacargahorariarealizada where cartacodigo = @cartacodigo

							-- INCLUI TOTALIZADORES
							exec dbo.spug_incluirTotalizadores @acordcodigo, @funcicodigo, @dt, 'spug_gerarCartaodePonto_background_update'

							-- ATUALIZA HORAS FALTA
							set @cartahorasfalta = (select horasfalta from dbo.retornarSomaHorasFuncionario(@cartacodigo))
							update tbgabcartaodeponto set 
							cartahorasfalta = @cartahorasfalta
							where cartacodigo = @cartacodigo
							
						end
					end
				end
				set @pk = @pk + 1
			end

			-- INCLUI OCORRÊNCIAS
			exec dbo.spug_incluirOcorrencias @mes,@ano, @funcicodigo
			-- INCLUI PERÍODOS NOTURNOS DE OCORRÊNCIAS
			exec dbo.incluirTempoNoturnoOcorrencias @funcicodigo, @mes, @ano
			-- INCLUI, EXCLUI OU ATUALIZA OS TOTALIZADORES MENSAIS
			declare acordos cursor for 
			select coalesce(acordcodigo,0) from tbgabcartaodeponto (nolock) 
			where funcicodigo = @funcicodigo and cartadatajornada between @periodoiniciodatabase and @periodofimdatabase and acordcodigo > 0 group by acordcodigo
			open acordos
			fetch next from acordos 
			into @acordcodigo
			while @@FETCH_STATUS=0
			begin
				exec dbo.spug_insereTotalizadoresSemanais @acordcodigo,@funcicodigo,@periodoiniciodatabase,@periodofimdatabase
				exec dbo.spug_insereTotalizadoresMensais @acordcodigo,@funcicodigo,@periodoiniciodatabase,@periodofimdatabase
			fetch next from acordos 
			into @acordcodigo
			end -- END CURSOR acordos
			close acordos
			deallocate acordos
			if @bancodehoras = 1 begin exec spug_incluirSaldoBhCartaodePonto @funcicodigo,@mes,@ano end

			-- INSERE
			insert into @cartaodeponto values (
			@mov_or_cc_bloq, -- 1
			@escala_vinculada, -- 2
			@func_ativo, -- 3
			@periodoiniciodatabase, -- 4
			@periodofimdatabase ) -- 5
		end -- END - SE POSSUI ESCALA VINCULADA PARA O PERÍODO INFORMADO
	end

	select top 1 sem_mov_or_cc_bloq,escala_vinculada,isnull(func_ativo,0),periodoinicio,periodofim from @cartaodeponto
	-- CORRIGE POSSÍVEIS ANOMALIAS DE O MESMO APONTAMENTO CONTER EM DOIS REGISTROS DIFERENTES NO CARTÃO 13/02/2020
	update tbgabcartaodeponto set carta_realizado_e1 = null, afdtgcodigo_e1 = null 
	where ctococodigo <> 1 and afdtgcodigo_e1 in 
	(select afdtgcodigo_e1 from tbgabcartaodeponto (nolock) 
	where funcicodigo = @funcicodigo and cartamesbase = @mes and cartaanobase = @ano and afdtgcodigo_e1 is not null group by afdtgcodigo_e1 having count(afdtgcodigo_e1) > 1)
END
GO

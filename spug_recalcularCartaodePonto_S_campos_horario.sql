SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




-- =============================================
-- Author:		Jean Paul
-- Create date: 06/11/2019
-- Description:	Recalcula o cartão de ponto fazendo as críticas.
-- =============================================

ALTER PROCEDURE [dbo].[spug_recalcularCartaodePonto_S_campos_horario] 
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
	@cartacodigo int,
	-- VARIÁVEIS USADAS NO CURSOR DE DADOS HISTÓRICOS
	@dt date,
	@horarcodigo int, -- valor recuperado da tabela cartão de ponto
	@ctococodigo int,
	@centccodigo int,
	@dia smallint,
	@feriado bit,
	@feriatipo char(1),
	@acordcodigo int,
	@cargocodigo int,
	@flagocorrencia bit,
	@nacional bit,
	@municipal bit,
	@regional bit,
	@jornadalivre bit,
	@inicionoturno datetime,
	@fimnoturno datetime,
	@fatornoturno float,
	@estendenoturno bit,
	@carta_realizado_e1 datetime, 
	@carta_realizado_s1 datetime,
	@carta_realizado_e2 datetime, 
	@carta_realizado_s2 datetime,
	@carta_realizado_e3 datetime, 
	@carta_realizado_s3 datetime,
	@carta_realizado_e4 datetime, 
	@carta_realizado_s4 datetime,
	@carta_previsto_e1 datetime,
	@carta_previsto_s1 datetime,
	@carta_previsto_e2 datetime,
	@carta_previsto_s2 datetime,
	@carta_previsto_e3 datetime,
	@carta_previsto_s3 datetime,
	@carta_previsto_e4 datetime,
	@carta_previsto_s4 datetime,
	@carta_tolerancia_anterior_e1 int,
	@carta_tolerancia_anterior_s1 int,
	@carta_tolerancia_posterior_e1 int,
	@carta_tolerancia_posterior_s1 int,
	@carta_tolerancia_anterior_e2 int,
	@carta_tolerancia_anterior_s2 int,
	@carta_tolerancia_posterior_e2 int,
	@carta_tolerancia_posterior_s2 int,
	@carta_tolerancia_anterior_e3 int,
	@carta_tolerancia_anterior_s3 int,
	@carta_tolerancia_posterior_e3 int,
	@carta_tolerancia_posterior_s3 int,
	@carta_tolerancia_anterior_e4 int,
	@carta_tolerancia_anterior_s4 int,
	@carta_tolerancia_posterior_e4 int,
	@carta_tolerancia_posterior_s4 int,
	@cartacargahorariarealizada int, 
	@cartacargahoraria int,
	@cartahorasfalta int, 
	@pis char(11),
	@aptr datetime,
	@num int,
	@contadorafd int,
	@contadorcartaodeponto int,
	@horaespera int = NULL,
	@horaparada int = NULL,
	@horadirecao int = NULL,
	@horaintervcpl int = NULL,
	@horaintervsdesc int = NULL,
	@horainterjornadacompl int = NULL,
	@horainterjornadacomplsdesc int = NULL,
	@leimotorista bit,
	-- INFORMA SE FUNCIONÁRIO É OU NÃO BANCO DE HORAS BASEADO NO DADO HISTÓRICO. ALTERAÇÃO FEITA EM 01/06/2020 POR JEAN PAUL.
	@bancodehoras bit,
	@afdtgcodigo int, @afdtgcodigo_e1 int,@afdtgcodigo_s1 int,@afdtgcodigo_e2 int,@afdtgcodigo_s2 int,@afdtgcodigo_e3 int,@afdtgcodigo_s3 int,@afdtgcodigo_e4 int,@afdtgcodigo_s4 int,
	@cartadesconsiderapreassinalado bit, @ctococodigooriginal smallint, @h_referencia smallint, @datademissao datetime

	select @pis = funcipis, @datademissao = funcidatademissao from tbgabfuncionario (nolock) where funcicodigo = @funcicodigo
	
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
			set @func_ativo = 1
			declare @recalcular bit,@escala bit, @vigencia datetime, @cod_escala int
			select @recalcular=recalcular, @escala = _esc, @vigencia = vigencia from dbo.verificarRecalculoCP(@funcicodigo,@periodoiniciodatabase,@periodofimdatabase,@mes,@ano)
			-- VERIFICA SE HÁ A NECESSIDADE DE SE RECALCULAR O CARTÃO
			if @recalcular = 1
			begin

				if (coalesce(@datademissao,'1900-01-01 00:00:00.000') = '1900-01-01 00:00:00.000')
				begin
					set @datademissao = @periodofimdatabase
				end

				-- ALTERAÇÃO 15/06/2020. ID DA DEMANDA: 36
				/* CÓDIGO IMPLEMENTADO */
				-- INÍCIO
				select @leimotorista = dbo.retornarSituacaoLeiMotoristaFuncionario(@funcicodigo,@periodoiniciodatabase,@periodofimdatabase)
				select @bancodehoras = dbo.retornarSituacaoBhFuncionario(@funcicodigo,@periodofimdatabase)
				-- FIM
				if @escala = 0 begin set @vigencia = dateadd(day,1,@periodofimdatabase) end
				declare @ctococodigo2 int = 0
				-- DELETA OS CARTÕES TOTALIZADORES DE OCORRÊNCIAS
				delete from tbgabcartaototalizador where funcicodigo = @funcicodigo and cartomesbase = @mes and cartoanobase = @ano and catcartocodigo in (9,10,14,15,17,114,115)

				-- RETORNAR DADOS HISTÓRICOS DO FUNCIONÁRIO	
				declare dados_historicos cursor for
				select cartacodigo,horarcodigo,cartadesconsiderapreassinalado,ctococodigo,ctococodigooriginal,cartadatajornada,cartaflagocorrencia,cartadiasemana,cartahorarreferencia
				from tbgabcartaodeponto (nolock) 
				where funcicodigo = @funcicodigo and cartadatajornada between @periodoiniciodatabase and @periodofimdatabase 
				and cartadatajornada <= @datademissao
				open dados_historicos
				fetch next from dados_historicos 
				into @cartacodigo,@horarcodigo,@cartadesconsiderapreassinalado,@ctococodigo,@ctococodigooriginal,@dt,@flagocorrencia,@dia,@h_referencia
				while @@FETCH_STATUS=0
				begin
				
					set @cartacargahorariarealizada = NULL
					set @carta_realizado_e1 = NULL
					set @carta_realizado_s1 = NULL
					set @carta_realizado_e2 = NULL
					set @carta_realizado_s2 = NULL
					set @carta_realizado_e3 = NULL
					set @carta_realizado_s3 = NULL
					set @carta_realizado_e4 = NULL
					set @carta_realizado_s4 = NULL
					set @feriado = 0
				
					-- RECUPERA O CENTRO DE CUSTO E O CARGO
					set @centccodigo = (select dbo.retornarCentroCustoPorData(@dt,@funcicodigo))
					if @centccodigo <> 0
					begin
						select top 1 @cargocodigo=cargocodigo from tbgabcentrocustofuncionario (nolock) where funcicodigo = @funcicodigo and cenfudatainicio <= @dt order by cenfudatainicio desc
					end
					else
					begin
						set @cargocodigo = 0
					end

					--RECUPERA O ACORDO COLETIVO DE DETERMINADA DATA
					set @acordcodigo = (select dbo.retornarAcordoPorData(@dt,@funcicodigo))

					-- VERIFICA SE O DIA É FERIADO
					set @feriado = (select case when count(F.feriacodigo) > 0 then 1 else 0 end from tbgabcentrocusto CC (nolock) 
									inner join tbgabtabelaferiadoferiado TF (nolock) on CC.fertbcodigo=tf.fertbcodigo
									inner join tbgabferiado F (nolock) on TF.feriacodigo=F.feriacodigo
									where CC.centccodigo = @centccodigo and F.feriames = @mes and F.feriadia = datepart(day,@dt))
				
					if @feriado > 0
					begin
						set @feriado = 1;
						set @feriatipo = (select top 1 F.fertpcodigo
						from tbgabcentrocusto CC (nolock) 
						inner join tbgabtabelaferiadoferiado TF (nolock) on CC.fertbcodigo=tf.fertbcodigo
						inner join tbgabferiado F (nolock) on TF.feriacodigo=F.feriacodigo
						where CC.centccodigo = @centccodigo and F.feriames = @mes and F.feriadia = datepart(day,@dt))
					end
					else
					begin
						set @feriado = 0;
						set @feriatipo = '';
					end
					
					-- SE NÃO HÁ ACORDO COLETIVO PARA O DIA
					if @acordcodigo = 0
					begin
						-- SE A INDICAÇÃO PARA O DIA FOR <> DE TRABALHO
						if @ctococodigo <> 1
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
						
					end

					-- SE HÁ ACORDO COLETIVO PARA O DIA
					else
					begin
						-- VERIFICA SE O ACORDO COLETIVO PARA O DIA É JORNADA LIVRE OU NÃO
						-- SENDO QUE SE A INDICAÇÃO FOR DIFERENTE DE TRABALHO A JORNADA SEMPRE SERÁ LIVRE
						if @ctococodigo = 1
						begin
							set @jornadalivre = (select acordjornadalivre from tbgabacordocoletivo (nolock) where acordcodigo = @acordcodigo)
						end
						else
						begin
							set @jornadalivre = 1
						end
						select 
						@inicionoturno=inicionoturno,
						@fimnoturno=fimnoturno,
						@fatornoturno=fatornoturno,
						@estendenoturno=estendenoturno from dbo.retornarInicioFimNoturno(@acordcodigo,@dt)
					end
					
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

					-- VERIFICA SE HÁ UMA NOVA ESCALA PARA ATUALIZAR O CARTÃO
					if @dt >= @vigencia
					begin
						set @cartacargahoraria = NULL
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

						--RECUPERA A ESCALA DE DETERMINADA DATA
						set @cod_escala = (select top 1 escalcodigo from tbgabfuncionarioescala (nolock) 
											where funcicodigo = @funcicodigo and fuescdatainiciovigencia <= @dt order by fuescdatainiciovigencia desc, fuescdatamovimentacao desc)

						--RECUPERA O HORÁRIO DE DETERMINADA DATA
						select @horarcodigo = F.codigohorario, @ctococodigo = CO.ctococodigo 
						from cjRetornarHorarioEscala (@cod_escala,@dt,@dt) F
						left join tbgabcartaoocorrencia CO (nolock) on F.indicacao= CO.ctocodescricao

						-- PREENCHE OS HORÁRIOS PREVISTOS
						if @horarcodigo <> 0
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
							from tbgabhorario (nolock) where horarcodigo = @horarcodigo

							select 
							@carta_previsto_e1=e1,@carta_previsto_s1=s1,
							@carta_previsto_e2=e2,@carta_previsto_s2=s2,
							@carta_previsto_e3=e3,@carta_previsto_s3=s3,
							@carta_previsto_e4=e4,@carta_previsto_s4=s4 
							from dbo.retornarHorariosPrevistos(@horarcodigo,@dt)
						end

						-- ALTERADO DIA 10/06/2020. SE HÁ CONFLITO DE ESCALAS, MUDA A REFERÊNCIA DE HORÁRIO
						if dbo.retornarConflitoEscala(@dt,@funcicodigo,@carta_previsto_e1) = 1 begin set @h_referencia = 2 end else begin set @h_referencia = 1 end

						-- CURSOR PARA RODAR OS APTS REALIZADOS
						DECLARE realizadas CURSOR FOR
						-- ALTERAÇÃO 15/06/2020. ID DA DEMANDA: 36
						select horarios,num,afdtgcodigo from dbo.retornarApontamentosRealizadosComPreAssinalados2(@funcicodigo,@dt,@horarcodigo,@jornadalivre,@ctococodigo,@cartadesconsiderapreassinalado,@h_referencia,/*CÓDIGO ALTERADO*/ @leimotorista /*CÓDIGO ALTERADO*/)
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
					
						if @ctococodigo = 0
						begin
							update tbgabcartaodeponto set ctococodigooriginal = @ctococodigo2,ctococodigo = @ctococodigo2 where cartacodigo = @cartacodigo
						end

						-- ATUALIZA VALORES
						update tbgabcartaodeponto set
						cargocodigo = @cargocodigo,
						funcicodigo = @funcicodigo,
						acordcodigo = @acordcodigo,
						horarcodigo = @horarcodigo,
						ctococodigo = @ctococodigo,
						cartacargahoraria = @cartacargahoraria,
						carta_previsto_e1 = @carta_previsto_e1,
						carta_previsto_s1 = @carta_previsto_s1,
						carta_previsto_e2 = @carta_previsto_e2,
						carta_previsto_s2 = @carta_previsto_s2,
						carta_previsto_e3 = @carta_previsto_e3,
						carta_previsto_s3 = @carta_previsto_s3,
						carta_previsto_e4 = @carta_previsto_e4,
						carta_previsto_s4 = @carta_previsto_s4,
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
						cartaadn = NULL,
						carta_tolerancia_anterior_e1 = @carta_tolerancia_anterior_e1,
						carta_tolerancia_posterior_e1 = @carta_tolerancia_posterior_e1,
						carta_tolerancia_anterior_s1 = @carta_tolerancia_anterior_s1,
						carta_tolerancia_posterior_s1 = @carta_tolerancia_posterior_s1,
						carta_tolerancia_anterior_e2 = @carta_tolerancia_anterior_e2,
						carta_tolerancia_posterior_e2 = @carta_tolerancia_posterior_e2,
						carta_tolerancia_anterior_s2 = @carta_tolerancia_anterior_s2,
						carta_tolerancia_posterior_s2 = @carta_tolerancia_posterior_s2,
						carta_tolerancia_anterior_e3 = @carta_tolerancia_anterior_e3,
						carta_tolerancia_posterior_e3 = @carta_tolerancia_posterior_e3,
						carta_tolerancia_anterior_s3 = @carta_tolerancia_anterior_s3,
						carta_tolerancia_posterior_s3 = @carta_tolerancia_posterior_s3,
						carta_tolerancia_anterior_e4 = @carta_tolerancia_anterior_e4,
						carta_tolerancia_posterior_e4 = @carta_tolerancia_posterior_e4,
						carta_tolerancia_anterior_s4 = @carta_tolerancia_anterior_s4,
						carta_tolerancia_posterior_s4 = @carta_tolerancia_posterior_s4,
						cartaflagferiado = @feriado,
						cartaflagocorrencia = @flagocorrencia,
						cartasaldoanteriorbh = NULL,
						cartacreditobh = NULL,
						cartadebitobh = NULL,
						cartasaldoatualbh = NULL,
						cartaespera = @horaespera,
						cartaparada = @horaparada,
						cartadirecao = @horadirecao,
						cartaintervcpl = @horaintervcpl,
						cartaintervsdesc = @horaintervsdesc,
						cartainterjornadacompl = @horainterjornadacompl,
						cartainterjornadacomplsdesc = @horainterjornadacomplsdesc,
						cartahorasextra = null,
						-- ALTERADO AQUI, 10/06/2020.
						cartahorarreferencia = @h_referencia
						--cartaprocessadopor = @usuarcodigo,
						--cartadataultimoprocessaamento = getdate()
						where cartacodigo = @cartacodigo
					end
					else
					begin
						-- CURSOR PARA RODAR OS APTS REALIZADOS
						DECLARE realizadas CURSOR FOR
						-- ALTERAÇÃO 15/06/2020. ID DA DEMANDA: 36
						select horarios,num,afdtgcodigo from dbo.retornarApontamentosRealizadosComPreAssinalados2(@funcicodigo,@dt,@horarcodigo,@jornadalivre,@ctococodigo,@cartadesconsiderapreassinalado,@h_referencia,/*CÓDIGO ALTERADO*/ @leimotorista /*CÓDIGO ALTERADO*/)
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
					
						if @ctococodigo = 0
						begin
							update tbgabcartaodeponto set ctococodigooriginal = @ctococodigo2,ctococodigo = @ctococodigo2 where cartacodigo = @cartacodigo
						end

						-- ATUALIZA VALORES
						update tbgabcartaodeponto set
						cargocodigo = @cargocodigo,
						acordcodigo = @acordcodigo,
						cartaferiadonacional = @nacional,										
						cartaferiadoregional = @regional,
						cartaferiadomunicipal = @municipal,
						centccodigo = @centccodigo,
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
						cartaadn = null,
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
						--cartaprocessadopor = @usuarcodigo,
						--cartadataultimoprocessaamento = getdate()
						where cartacodigo = @cartacodigo
					end

					-- PEGA HORA REALIZADA
					set @cartacargahorariarealizada = (select minuto from dbo.retornarSomaHorasFuncionario(@cartacodigo))
					
					-- ATUALIZA HORA REALIZADA
					update tbgabcartaodeponto set cartacargahorariarealizada = @cartacargahorariarealizada where cartacodigo = @cartacodigo
				
					-- INCLUI TOTALIZADORES
					exec dbo.spug_incluirTotalizadores @acordcodigo, @funcicodigo, @dt, 'spug_recalcularCartaodePonto_S_campos_horario'
				
					-- ATUALIZA HORAS FALTA
					set @cartahorasfalta = (select horasfalta from dbo.retornarSomaHorasFuncionario(@cartacodigo))
					update tbgabcartaodeponto set cartahorasfalta = @cartahorasfalta where cartacodigo = @cartacodigo
				
				fetch next from dados_historicos 
				into @cartacodigo,@horarcodigo,@cartadesconsiderapreassinalado,@ctococodigo,@ctococodigooriginal,@dt,@flagocorrencia,@dia,@h_referencia
				end -- END CURSOR dados_historicos
				close dados_historicos
				deallocate dados_historicos

				-- INCLUI OCORRÊNCIAS
				exec dbo.spug_incluirOcorrencias @mes,@ano, @funcicodigo 
				-- INCLUI PERÍODOS NOTURNOS DE OCORRÊNCIAS
				exec dbo.incluirTempoNoturnoOcorrencias @funcicodigo, @mes, @ano
			
				-- INCLUI, EXCLUI OU ATUALIZA OS TOTALIZADORES MENSAIS
				declare acordos cursor for 
				select coalesce(acordcodigo,0) from tbgabcartaodeponto (nolock) 
				where funcicodigo = @funcicodigo and cartadatajornada between @periodoiniciodatabase and @periodofimdatabase group by acordcodigo
				open acordos
				fetch next from acordos 
				into @acordcodigo
				while @@FETCH_STATUS=0
				begin
					exec dbo.spug_insereTotalizadoresSemanais @acordcodigo,@funcicodigo,@periodoiniciodatabase,@periodofimdatabase
					exec dbo.spug_insereTotalizadoresMensais @acordcodigo,@funcicodigo,@periodoiniciodatabase,@periodofimdatabase
					--exec dbo.spug_limparCartoesTotalizadores @funcicodigo, @mes, @ano, @acordcodigo 
				fetch next from acordos 
				into @acordcodigo
				end -- END CURSOR acordos
				close acordos
				deallocate acordos
				if @bancodehoras = 1 
				begin
					exec spug_incluirSaldoBhCartaodePonto @funcicodigo,@mes,@ano
				end
				-- ATUALIZA O HEADER DO CARTÃO DE PONTO
				--exec dbo.CartaoDePontoHeader @funcicodigo,@mes,@ano
			end
			-- ATUALIZA VALORES
			update tbgabcartaodeponto set cartaprocessadopor = @usuarcodigo, cartadataultimoprocessaamento = getdate() where funcicodigo = @funcicodigo and cartamesbase = @mes and cartaanobase = @ano
			insert into @cartaodeponto values (
			@mov_or_cc_bloq, -- 1
			@escala_vinculada, -- 2
			@func_ativo, -- 3
			@periodoiniciodatabase, -- 4
			@periodofimdatabase) -- 5
		end
	end

	select top 1 sem_mov_or_cc_bloq,escala_vinculada,func_ativo,periodoinicio,periodofim from @cartaodeponto
	-- CORRIGE POSSÍVEIS ANOMALIAS DE O MESMO APONTAMENTO CONTER EM DOIS REGISTROS DIFERENTES NO CARTÃO 13/02/2020
	update tbgabcartaodeponto set carta_realizado_e1 = null, afdtgcodigo_e1 = null 
	where ctococodigo <> 1 and afdtgcodigo_e1 in 
	(select afdtgcodigo_e1 from tbgabcartaodeponto (nolock) 
	where funcicodigo = @funcicodigo and cartamesbase = @mes and cartaanobase = @ano and afdtgcodigo_e1 is not null group by afdtgcodigo_e1 having count(afdtgcodigo_e1) > 1)
END
GO

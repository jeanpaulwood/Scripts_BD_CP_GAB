SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Jean Paul
-- Create date: 19/07/2019
-- Description:	Recalcula o cartão de ponto fazendo as críticas.
-- =============================================
-- ATUALIZAÇÕES
-- =============================================
-- Author:		Jean Paul
-- alter date: 30/07/2019
-- 1º Trocado a SP incluiOcorrencias de lugar, para dentro do cursor de dias pois quando funcionário em mais de um acordo coletivo, chama a SP mais de uma vez.
-- 2º alter date: 08/08/2019 Implementado os campos relacionados a lei do motorista
-- alter date: 23/08/2019
-- 1º Implementado a SP que atualiza o saldo e o saldo anterior do funcionário no CP
-- =============================================
alter PROCEDURE [dbo].[spug_recalcularCartaodePonto_dia_background] 
	-- Add the parameters for the function here
	@funcicodigo int,@mes smallint, @ano int, @usuarcodigo int, @cartadatajornada datetime, @itprocodigo int
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
	@cartasaldobh int,
	@cartacreditobh int,
	@cartadebitobh int,
	@cartasaldoanterior int,
	-- VARIÁVEIS USADAS NO CURSOR DE DADOS HISTÓRICOS
	@dia smallint,
	@dt date,
	@codigo_h int,
	@horarcodigo int, -- valor recuperado da tabela cartão de ponto
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
	@contadorafd int,
	@contadorcartaodeponto int,
	@ult_apt datetime = NULL,
	@dt_auxiliar datetime = NULL,
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
	@compljornada int, -- INFORMA SE EVENTO COMPLEMENTA OU NÃO A JORNADA DO DIA
	@contjornada int,
	@afdtgcodigo int, @afdtgcodigo_e1 int,@afdtgcodigo_s1 int,@afdtgcodigo_e2 int,@afdtgcodigo_s2 int,@afdtgcodigo_e3 int,@afdtgcodigo_s3 int,@afdtgcodigo_e4 int,@afdtgcodigo_s4 int,
	@cartadesconsiderapreassinalado bit, @ctococodigooriginal smallint, @h_referencia smallint, @datademissao datetime
	
	select @pis = funcipis, @datademissao = funcidatademissao from tbgabfuncionario (nolock) where funcicodigo = @funcicodigo
	
	if (coalesce(@datademissao,'1900-01-01 00:00:00.000') = '1900-01-01 00:00:00.000')
	begin
		set @datademissao = @cartadatajornada
	end
	
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

		-- ALTERAÇÃO 15/06/2020. ID DA DEMANDA: 36
		/* CÓDIGO IMPLEMENTADO */
		-- INÍCIO
		select @leimotorista = dbo.retornarSituacaoLeiMotoristaFuncionario(@funcicodigo,@periodoiniciodatabase,@periodofimdatabase)
		select @bancodehoras = dbo.retornarSituacaoBhFuncionario(@funcicodigo,@periodofimdatabase)
		-- FIM
		set @func_ativo = 1
		declare @ctococodigo2 int = 0

		-- DELETA OS CARTÕES TOTALIZADORES DE OCORRÊNCIAS
		delete from tbgabcartaototalizador where funcicodigo = @funcicodigo and cartodatajornada = @cartadatajornada and catcartocodigo in (9,10,14,15,17,114,115)

		-- RETORNAR DADOS HISTÓRICOS DO FUNCIONÁRIO	
		select 
		@cartacodigo = coalesce(cartacodigo,0),@horarcodigo = horarcodigo,
		@cartadesconsiderapreassinalado = cartadesconsiderapreassinalado,
		@ctococodigo = ctococodigo,@ctococodigooriginal = ctococodigooriginal,
		@flagocorrencia = cartaflagocorrencia,@dia = cartadiasemana, @h_referencia=cartahorarreferencia
		from tbgabcartaodeponto (nolock) where funcicodigo = @funcicodigo and cartadatajornada = @cartadatajornada
		
		if @cartacodigo <> 0 and @cartadatajornada <= @datademissao 
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
			
			-- RECUPERA O CENTRO DE CUSTO E O CARGO
			set @centccodigo = (select dbo.retornarCentroCustoPorData(@cartadatajornada,@funcicodigo))
			if @centccodigo <> 0
			begin
				select top 1 @cargocodigo=cargocodigo from tbgabcentrocustofuncionario (nolock) where funcicodigo = @funcicodigo and cenfudatainicio <= @cartadatajornada order by cenfudatainicio desc
			end
			else
			begin
				set @cargocodigo = 0
			end

			--RECUPERA O ACORDO COLETIVO DE DETERMINADA DATA
			set @acordcodigo = (select dbo.retornarAcordoPorData(@cartadatajornada,@funcicodigo))

			-- VERIFICA SE O DIA É FERIADO
			set @feriado = (select case when count(F.feriacodigo) > 0 then 1 else 0 end from tbgabcentrocusto CC (nolock) 
							inner join tbgabtabelaferiadoferiado TF (nolock) on CC.fertbcodigo=tf.fertbcodigo
							inner join tbgabferiado F (nolock) on TF.feriacodigo=F.feriacodigo
							where CC.centccodigo = @centccodigo and F.feriames = @mes and F.feriadia = datepart(day,@cartadatajornada))

			if @feriado > 0
			begin
				set @feriado = 1;
				set @feriatipo = (select top 1 F.fertpcodigo
				from tbgabcentrocusto CC (nolock) 
				inner join tbgabtabelaferiadoferiado TF (nolock) on CC.fertbcodigo=tf.fertbcodigo
				inner join tbgabferiado F (nolock) on TF.feriacodigo=F.feriacodigo
				where CC.centccodigo = @centccodigo and F.feriames = @mes and F.feriadia = datepart(day,@cartadatajornada))
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
				@estendenoturno=estendenoturno from dbo.retornarInicioFimNoturno(@acordcodigo,@cartadatajornada)
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

			-- CURSOR PARA RODAR OS APTS REALIZADOS
			DECLARE realizadas CURSOR FOR
			-- ALTERAÇÃO 15/06/2020. ID DA DEMANDA: 36
			select horarios,num,afdtgcodigo from dbo.retornarApontamentosRealizadosComPreAssinalados2(@funcicodigo,@cartadatajornada,@horarcodigo,@jornadalivre,@ctococodigo,@cartadesconsiderapreassinalado,@h_referencia,/*CÓDIGO ALTERADO*/ @leimotorista /*CÓDIGO ALTERADO*/)
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
				set @horaespera = (select sum(horasespera) from dbo.retornarTempoEsperaLeidoMotorista(@pis,@cartadatajornada))
				set @horaparada = (select sum(horasparada) from dbo.retornarTempoParadaLeidoMotorista(@pis,@cartadatajornada))
				set @horadirecao = (select sum(horasdirecao) from dbo.retornarTempoDirecaoLeidoMotorista(@pis,@cartadatajornada))
				set @horaintervcpl = (select sum(horasintervcpl) from dbo.retornarTempoIntervCplLeidoMotorista(@pis,@cartadatajornada))
				set @horaintervsdesc = (select sum(horasintervsemdesc) from dbo.retornarTempoIntervSemDescLeidoMotorista(@pis,@cartadatajornada))
				set @horainterjornadacompl = (select sum(horasinterjornadacompl) from dbo.retornarTempoInterjornadaComplLeidoMotorista(@pis,@cartadatajornada))
				set @horainterjornadacomplsdesc = (select SUM(horasinterjornadasdesc) from dbo.retornarTempoInterjornadaSemDescLeidoMotorista(@pis,@cartadatajornada))
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
			cartahorasextra = null,
			--cartaprocessadopor = @usuarcodigo,
			--cartadataultimoprocessaamento = getdate(),
			cartadataalteracao = getdate(),
			cartausuaralteracao = @usuarcodigo
			where cartacodigo = @cartacodigo

			-- PEGA HORA REALIZADA
			set @cartacargahorariarealizada = (select minuto from dbo.retornarSomaHorasFuncionario(@cartacodigo))
				
			-- ATUALIZA HORA REALIZADA
			update tbgabcartaodeponto set cartacargahorariarealizada = @cartacargahorariarealizada where cartacodigo = @cartacodigo
			
			-- INCLUI TOTALIZADORES
			exec dbo.spug_incluirTotalizadores @acordcodigo, @funcicodigo, @cartadatajornada, 'spug_recalcularCartaodePonto_dia_background'
			
			-- ATUALIZA HORAS FALTA
			set @cartahorasfalta = (select horasfalta from dbo.retornarSomaHorasFuncionario(@cartacodigo))
			update tbgabcartaodeponto set cartahorasfalta = @cartahorasfalta where cartacodigo = @cartacodigo
			
			insert into @cartaodeponto values (
			@mov_or_cc_bloq, -- 1
			@escala_vinculada, -- 2
			@func_ativo, -- 3
			@periodoiniciodatabase, -- 4
			@periodofimdatabase) -- 5

			-- INCLUI OCORRÊNCIAS
			exec dbo.spug_incluirOcorrencias_dia @mes,@ano, @funcicodigo,@cartadatajornada
			-- INCLUI PERÍODOS NOTURNOS DE OCORRÊNCIAS
			exec dbo.incluirTempoNoturnoOcorrencias_dia @funcicodigo, @mes, @ano, @cartadatajornada
		
			if @acordcodigo <> 0
			begin
				-- INCLUI, EXCLUI OU ATUALIZA OS TOTALIZADORES MENSAIS
				exec dbo.spug_insereTotalizadoresSemanais @acordcodigo,@funcicodigo,@periodoiniciodatabase,@periodofimdatabase
				exec dbo.spug_insereTotalizadoresMensais @acordcodigo,@funcicodigo,@periodoiniciodatabase,@periodofimdatabase
				--exec dbo.spug_limparCartoesTotalizadores @funcicodigo, @mes, @ano, @acordcodigo 
			end
			if @bancodehoras = 1 
			begin
				exec spug_incluirSaldoBhCartaodePonto_DIA @funcicodigo,@mes,@ano,@cartadatajornada
			end
		end
		-- ATUALIZA O HEADER DO CARTÃO DE PONTO
		--exec dbo.CartaoDePontoHeader @funcicodigo,@mes,@ano
			
	end

	--select top 1 sem_mov_or_cc_bloq,escala_vinculada,func_ativo,periodoinicio,periodofim from @cartaodeponto
	declare @obs varchar(max) = '';
	declare @haserror bit = 0;

	if (select top 1 sem_mov_or_cc_bloq from @cartaodeponto) = 1
	begin 
		set @obs += 'Sem movimentação ou centro de custo bloqueado;';set @haserror = 1;
	end

	if (select top 1 escala_vinculada from @cartaodeponto) = 0
	begin 
		set @obs += 'Sem escala vinculada;';set @haserror = 1;
	end

	if (select top 1 func_ativo from @cartaodeponto) = 0
	begin 
		set @obs += 'Funcionário inativo;';set @haserror = 1;
	end

	if @haserror = 0
	begin
		update tbgabitemprocessamento set itproobservacao = @obs,itprosituacao = 3 where itprocodigo = @itprocodigo
	end
	else
	begin
		update tbgabitemprocessamento set itproobservacao = @obs,itprosituacao = 4 where itprocodigo = @itprocodigo
	end
	-- CORRIGE POSSÍVEIS ANOMALIAS DE O MESMO APONTAMENTO CONTER EM DOIS REGISTROS DIFERENTES NO CARTÃO 13/02/2020
	update tbgabcartaodeponto set carta_realizado_e1 = null, afdtgcodigo_e1 = null 
	where ctococodigo <> 1 and afdtgcodigo_e1 in 
	(select afdtgcodigo_e1 from tbgabcartaodeponto (nolock) 
	where funcicodigo = @funcicodigo and cartamesbase = @mes and cartaanobase = @ano and afdtgcodigo_e1 is not null group by afdtgcodigo_e1 having count(afdtgcodigo_e1) > 1)
END
GO
